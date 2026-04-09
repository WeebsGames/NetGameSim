#include <mpi.h>
#include <iostream>
#include <string>
#include <vector>
#include <fstream>
#include <sstream>
#include <chrono>
#include <iomanip>
#include <filesystem>
#include <unordered_map>
#include <limits>
#include <queue>
#include <cmath>

#include "../include/graph.hpp"

namespace fs = std::filesystem;

#include <json_header/nlohmann/json.hpp>
using nlohmann::json;

static std::string read_seed_from_graph_manifest() {
    // Best-effort: read outputs/graph.manifest.json and return the 'seed' as string; empty if missing
    std::ifstream is("outputs/graph.manifest.json");
    if (!is) return std::string();
    try {
        json j; is >> j;
        if (j.contains("seed") && !j.at("seed").is_null()) {
            return j.at("seed").get<std::string>();
        }
    } catch (...) {
        return std::string();
    }
    return std::string();
}

struct CmdArgs {
    std::string graphPath;
    std::string partPath;
    std::string algo; // leader | dijkstra
    int rounds = 0;   // optional for leader
    int source = 0;   // for dijkstra
    std::string logDir = "outputs/";
    bool verbose = false;
};

static void write_run_manifest(const std::string& algo,
                               const CmdArgs& args,
                               int world_size,
                               const std::string& start_time,
                               const std::string& end_time,
                               long long runtime_ms,
                               const std::string& seed) {
    std::string file = args.logDir;
    if (!file.empty() && file.back() != '/' && file.back() != '\\') file += "/";
    file += "run_manifest.json";
    fs::create_directories(args.logDir);

    // Best-effort: compute simple sizes instead of SHA-256 to avoid extra deps
    auto file_size_or_neg = [](const std::string& p)->long long {
        std::error_code ec; auto sz = fs::file_size(p, ec); return ec ? -1LL : static_cast<long long>(sz);
    };

    std::ofstream os(file, std::ios::trunc);
    os << "{\n";
    os << "  \"algo\": \"" << algo << "\",\n";
    os << "  \"ranks\": " << world_size << ",\n";
    os << "  \"graph_path\": \"" << args.graphPath << "\",\n";
    os << "  \"part_path\": \"" << args.partPath << "\",\n";
    os << "  \"start_time\": \"" << start_time << "\",\n";
    os << "  \"end_time\": \"" << end_time << "\",\n";
    os << "  \"runtime_ms\": " << runtime_ms << ",\n";
    os << "  \"seed\": \"" << seed << "\",\n";
    os << "  \"graph_size_bytes\": " << file_size_or_neg(args.graphPath) << ",\n";
    os << "  \"part_size_bytes\": " << file_size_or_neg(args.partPath) << "\n";
    os << "}\n";
}

static void print_help(int rank) {
    if (rank == 0) {
        std::cout << "ngs_mpi (C++17, OpenMPI)\n"
                  << "Usage: ngs_mpi --graph <path> --part <path> --algo <leader|dijkstra> [--rounds N] [--source S] [--log outputs/] [--verbose]\n";
    }
}

static CmdArgs parse_args(int argc, char** argv, int rank) {
    CmdArgs a;
    for (int i = 1; i < argc; ++i) {
        std::string s = argv[i];
        if (s == "--help" || s == "-h") {
            print_help(rank);
            MPI_Abort(MPI_COMM_WORLD, 0);
        } else if (s == "--graph" && i + 1 < argc) {
            a.graphPath = argv[++i];
        } else if (s == "--part" && i + 1 < argc) {
            a.partPath = argv[++i];
        } else if (s == "--algo" && i + 1 < argc) {
            a.algo = argv[++i];
        } else if (s == "--rounds" && i + 1 < argc) {
            a.rounds = std::stoi(argv[++i]);
        } else if (s == "--source" && i + 1 < argc) {
            a.source = std::stoi(argv[++i]);
        } else if (s == "--log" && i + 1 < argc) {
            a.logDir = argv[++i];
        } else if (s == "--verbose") {
            a.verbose = true;
        } else {
            if (rank == 0) {
                std::cerr << "Unknown or incomplete argument: " << s << "\n";
            }
            print_help(rank);
            MPI_Abort(MPI_COMM_WORLD, 1);
        }
    }
    if (a.graphPath.empty() || a.partPath.empty() || a.algo.empty()) {
        if (rank == 0) {
            std::cerr << "Missing required arguments.\n";
        }
        print_help(rank);
        MPI_Abort(MPI_COMM_WORLD, 1);
    }
    return a;
}

static std::string now_iso8601() {
    using namespace std::chrono;
    auto tp = system_clock::now();
    std::time_t t = system_clock::to_time_t(tp);
    std::tm tm = *std::gmtime(&t);
    auto ms = duration_cast<milliseconds>(tp.time_since_epoch()) % 1000;
    std::ostringstream oss;
    oss << std::put_time(&tm, "%Y-%m-%dT%H:%M:%S") << "." << std::setw(3) << std::setfill('0') << ms.count() << "Z";
    return oss.str();
}

static void rank_log(const std::string& baseDir, int rank, const std::string& algo, const std::string& line) {
    fs::create_directories(fs::path(baseDir) / "logs");
    std::ostringstream fn;
    fn << baseDir;
    if (!baseDir.empty() && baseDir.back() != '/' && baseDir.back() != '\\') fn << "/";
    fn << "logs/" << algo << "_rank" << rank << ".log";
    std::ofstream out(fn.str(), std::ios::app);
    out << now_iso8601() << " rank=" << rank << " " << line << "\n";
}

static void write_summary_json(const std::string& algo,
                               const CmdArgs& args,
                               int world_size,
                               long iterations,
                               long messages,
                               long bytes,
                               long long runtime_ms,
                               const std::string& start_time,
                               const std::string& end_time,
                               const std::string& seed,
                               const std::string& extra_json,
                               const std::string& histogram_json) {
    // Rank 0 writes: outputs/summary_<algo>.json under args.logDir
    std::string file = args.logDir;
    if (!file.empty() && file.back() != '/' && file.back() != '\\') file += "/";
    file += (std::string("summary_") + algo + ".json");
    fs::create_directories(args.logDir);
    std::ofstream os(file, std::ios::trunc);
    os << "{\n";
    os << "  \"algo\": \"" << algo << "\",\n";
    os << "  \"ranks\": " << world_size << ",\n";
    os << "  \"graph_path\": \"" << args.graphPath << "\",\n";
    os << "  \"part_path\": \"" << args.partPath << "\",\n";
    os << "  \"iterations\": " << iterations << ",\n";
    os << "  \"messages_sent\": " << messages << ",\n";
    os << "  \"bytes_sent\": " << bytes << ",\n";
    os << "  \"runtime_ms\": " << runtime_ms << ",\n";
    os << "  \"start_time\": \"" << start_time << "\",\n";
    os << "  \"end_time\": \"" << end_time << "\",\n";
    os << "  \"seed\": \"" << seed << "\",\n";
    if (!extra_json.empty()) {
        os << "  \"result\": " << extra_json << ",\n";
    }
    if (!histogram_json.empty()) {
        os << "  \"distance_histogram\": " << histogram_json << ",\n";
    }
    os << "  \"args\": { \"rounds\": " << args.rounds << ", \"source\": " << args.source << ", \"verbose\": " << (args.verbose?1:0) << " }\n";
    os << "}\n";
}

int main(int argc, char** argv) {
    std::string summary_extra_json;
    std::string histogram_json; // optional: distance histogram for dijkstra
    MPI_Init(&argc, &argv);

    int world_rank = -1;
    int world_size = 0;
    MPI_Comm_rank(MPI_COMM_WORLD, &world_rank);
    MPI_Comm_size(MPI_COMM_WORLD, &world_size);

    if (world_rank == 0) {
        std::cout << "Starting ngs_mpi with " << world_size << " ranks" << std::endl;
    }

    CmdArgs args = parse_args(argc, argv, world_rank);

    // Ensure base log directory exists
    fs::create_directories(args.logDir);

    if (world_rank == 0) {
        std::cout << "Args: algo=" << args.algo
                  << ", graph=" << args.graphPath
                  << ", part=" << args.partPath
                  << ", rounds=" << args.rounds
                  << ", source=" << args.source
                  << ", logDir=" << args.logDir
                  << ", verbose=" << (args.verbose ? "true" : "false")
                  << std::endl;
    }

    // Timing start
    std::string start_str = now_iso8601();
    auto t0 = std::chrono::steady_clock::now();

    long iterations = 0;
    long messages = 0;
    long bytes = 0;

    // Stubs: algorithms to be implemented next phases.
    if (args.algo == "leader") {
        // Correctness-first leader election: global max node id via Allreduce.
        // This achieves agreement in one iteration and provides a baseline.
        rank_log(args.logDir, world_rank, "leader", "Starting leader election (global-max baseline)");
        try {
            GraphData gd = load_two_line_graph_json(args.graphPath);
            PartitionData pd = load_partition_json(args.partPath);
            if (pd.ranks != world_size) {
                if (world_rank == 0) {
                    std::cerr << "Partition ranks (" << pd.ranks << ") do not match MPI world size (" << world_size << ")" << std::endl;
                }
                MPI_Abort(MPI_COMM_WORLD, 3);
            }
            RankView rv = build_rank_view(gd, pd, world_rank, world_size);

            // Local candidate = max owned node id (or -1 if none)
            int local_max = -1;
            for (int id : rv.owned_nodes) if (id > local_max) local_max = id;
            // Reduce to global max across ranks
            int global_max = -1;
            MPI_Allreduce(&local_max, &global_max, 1, MPI_INT, MPI_MAX, MPI_COMM_WORLD);
            messages += 1; bytes += sizeof(int);

            // Agreement check (trivial here, but keep pattern)
            int agree = (global_max >= 0) ? 1 : 0;
            int all_agree = 0;
            MPI_Allreduce(&agree, &all_agree, 1, MPI_INT, MPI_LAND, MPI_COMM_WORLD);
            messages += 1; bytes += sizeof(int);

            iterations = 1; // single collective step baseline
            std::ostringstream oss;
            oss << "Elected leader id=" << global_max << ", owned_nodes=" << rv.owned_nodes.size();
            rank_log(args.logDir, world_rank, "leader", oss.str());

            if (world_rank == 0) {
                // include leader id in the summary 'result' field for tests
                std::ostringstream rj; rj << "{\"leader\":" << global_max << "}";
                summary_extra_json = rj.str();
            }
            if (world_rank == 0 && args.verbose) {
                std::cout << "[leader] Elected leader id=" << global_max << std::endl;
            }
        } catch (const std::exception& ex) {
            if (world_rank == 0) std::cerr << "Leader setup failed: " << ex.what() << std::endl;
            MPI_Abort(MPI_COMM_WORLD, 6);
        }
        rank_log(args.logDir, world_rank, "leader", "Finished leader election (global-max baseline)");
    } else if (args.algo == "dijkstra") {
        try {
            if (world_rank == 0) std::cout << "[dijkstra] Loading inputs..." << std::endl;
            GraphData gd = load_two_line_graph_json(args.graphPath);
            PartitionData pd = load_partition_json(args.partPath);
            if (pd.ranks != world_size) {
                if (world_rank == 0) {
                    std::cerr << "Partition ranks (" << pd.ranks << ") do not match MPI world size (" << world_size << ")" << std::endl;
                }
                MPI_Abort(MPI_COMM_WORLD, 3);
            }
            RankView rv = build_rank_view(gd, pd, world_rank, world_size);
            std::ostringstream ss;
            ss << "Loaded graph: N=" << gd.num_nodes << ", E=" << gd.edges.size()
               << "; owned=" << rv.owned_nodes.size() << ", ghosts=" << rv.ghosts.size();
            rank_log(args.logDir, world_rank, "dijkstra", ss.str());

            // Distributed Dijkstra (global-min baseline)
            const double INF = std::numeric_limits<double>::infinity();
            std::unordered_map<int,double> dist;          // tentative distances for nodes we learn about
            std::unordered_map<int,bool> settled;         // settled flags for owned nodes

            // Min-heap for owned unsettled nodes (dist, node)
            using PQItem = std::pair<double,int>;
            struct Cmp { bool operator()(const PQItem& a, const PQItem& b) const { return a.first > b.first; } };
            std::priority_queue<PQItem, std::vector<PQItem>, Cmp> pq;

            auto getdist = [&](int id)->double {
                auto it = dist.find(id); return it==dist.end()? INF : it->second;
            };
            auto setdist = [&](int id, double d){ dist[id] = d; };
            auto owner_of = [&](int id)->int {
                auto it = pd.owner_of.find(id); return (it==pd.owner_of.end()? -1 : it->second);
            };

            // Initialize source
            int src_owner = owner_of(args.source);
            if (src_owner < 0) {
                if (world_rank == 0) std::cerr << "Source node not present in owner map: " << args.source << std::endl;
                MPI_Abort(MPI_COMM_WORLD, 5);
            }
            if (world_rank == src_owner) {
                setdist(args.source, 0.0);
                pq.push({0.0, args.source});
            }

            long iters = 0;
            long msg = 0;
            long by = 0;

            // Iteration loop
            while (true) {
                // 1) Each rank proposes its best local candidate
                double my_best_d = INF;
                int my_best_node = -1;
                int my_best_owner = -1;
                while (!pq.empty()) {
                    auto top = pq.top();
                    double d = top.first; int u = top.second;
                    if (settled[u]) { pq.pop(); continue; }
                    my_best_d = d; my_best_node = u; my_best_owner = owner_of(u);
                    break;
                }

                // 2) Gather proposals to rank 0
                std::vector<double> all_d; std::vector<int> all_n; std::vector<int> all_o;
                if (world_rank == 0) {
                    all_d.resize(world_size, INF);
                    all_n.resize(world_size, -1);
                    all_o.resize(world_size, -1);
                }
                double send_d = my_best_d;
                int send_n = my_best_node;
                int send_o = my_best_owner;
                MPI_Gather(&send_d, 1, MPI_DOUBLE, all_d.data(), 1, MPI_DOUBLE, 0, MPI_COMM_WORLD);
                MPI_Gather(&send_n, 1, MPI_INT,    all_n.data(), 1, MPI_INT,    0, MPI_COMM_WORLD);
                MPI_Gather(&send_o, 1, MPI_INT,    all_o.data(), 1, MPI_INT,    0, MPI_COMM_WORLD);
                msg += 3; by += static_cast<long>(world_size*sizeof(double) + 2*world_size*sizeof(int));

                // 3) Rank 0 selects global min and broadcasts choice
                double sel_d = INF; int sel_node = -1; int sel_owner = -1;
                if (world_rank == 0) {
                    for (int r = 0; r < world_size; ++r) {
                        if (all_n[r] >= 0 && all_d[r] < sel_d) {
                            sel_d = all_d[r]; sel_node = all_n[r]; sel_owner = all_o[r];
                        }
                    }
                }
                MPI_Bcast(&sel_d, 1, MPI_DOUBLE, 0, MPI_COMM_WORLD);
                MPI_Bcast(&sel_node, 1, MPI_INT, 0, MPI_COMM_WORLD);
                MPI_Bcast(&sel_owner, 1, MPI_INT, 0, MPI_COMM_WORLD);
                msg += 3; by += static_cast<long>(sizeof(double) + 2*sizeof(int));

                // Termination if no candidate remains
                if (sel_node < 0 || sel_d == INF) {
                    break;
                }

                // 4) Owning rank settles node and relaxes its outgoing edges
                std::vector<int> upd_ids; std::vector<double> upd_dists;
                if (world_rank == sel_owner) {
                    settled[sel_node] = true;
                    // Remove top if matches; cleanup handled lazily above
                    auto it_idx = gd.id_to_idx.find(sel_node);
                    if (it_idx != gd.id_to_idx.end()) {
                        int idx = it_idx->second;
                        const auto& outs = gd.adj[idx];
                        for (const auto& e : outs) {
                            int v = e.to; double nd = sel_d + e.cost;
                            double prev = getdist(v);
                            if (nd + 1e-12 < prev) {
                                setdist(v, nd);
                                if (owner_of(v) == world_rank && !settled[v]) {
                                    pq.push({nd, v});
                                }
                                upd_ids.push_back(v);
                                upd_dists.push_back(nd);
                            }
                        }
                    }
                }

                // 5) Broadcast updates from owning rank to all
                int upd_count = static_cast<int>(upd_ids.size());
                MPI_Bcast(&upd_count, 1, MPI_INT, sel_owner, MPI_COMM_WORLD);
                msg += 1; by += static_cast<long>(sizeof(int));
                if (upd_count > 0) {
                    if (world_rank != sel_owner) {
                        upd_ids.resize(upd_count);
                        upd_dists.resize(upd_count);
                    }
                    MPI_Bcast(upd_ids.data(), upd_count, MPI_INT, sel_owner, MPI_COMM_WORLD);
                    MPI_Bcast(upd_dists.data(), upd_count, MPI_DOUBLE, sel_owner, MPI_COMM_WORLD);
                    msg += 2; by += static_cast<long>(upd_count*sizeof(int) + upd_count*sizeof(double));
                }

                // Apply updates locally (all ranks)
                for (int i = 0; i < (int)upd_ids.size(); ++i) {
                    int v = upd_ids[i]; double nd = upd_dists[i];
                    double prev = getdist(v);
                    if (nd + 1e-12 < prev) {
                        setdist(v, nd);
                        if (owner_of(v) == world_rank && !settled[v]) {
                            pq.push({nd, v});
                        }
                    }
                }

                ++iters;
                if (args.verbose && world_rank == 0 && (iters % 10 == 0)) {
                    std::cout << "[dijkstra] iter=" << iters << ", sel_node=" << sel_node << ", sel_d=" << sel_d << std::endl;
                }
            }

            // After Dijkstra loop: gather final distances to rank 0 and build histogram
            {
                // Build local dense vector over known node ids (index by gd.id_to_idx)
                const int N = static_cast<int>(gd.node_ids.size());
                const double INF = std::numeric_limits<double>::infinity();
                std::vector<double> localD(N, INF);
                for (const auto &kv : gd.id_to_idx) {
                    int id = kv.first; int idx = kv.second;
                    auto it = dist.find(id);
                    if (it != dist.end()) localD[idx] = it->second;
                }
                std::vector<double> globalD(N, INF);
                MPI_Allreduce(localD.data(), globalD.data(), N, MPI_DOUBLE, MPI_MIN, MPI_COMM_WORLD);
                msg += 1; by += static_cast<long>(N * sizeof(double));

                if (world_rank == 0) {
                    // Build a result.dist_map {"id": dist}
                    std::ostringstream rj;
                    rj << "{\"source\":" << args.source << ",\"dist_map\":{";
                    for (size_t i = 0; i < gd.node_ids.size(); ++i) {
                        int id = gd.node_ids[i];
                        double d = globalD[gd.id_to_idx.at(id)];
                        if (i > 0) rj << ",";
                        // Emit integers without trailing .0 when close to integer
                        rj << "\"" << id << "\":" << std::setprecision(15) << d;
                    }
                    rj << "}}";
                    summary_extra_json = rj.str();

                    // Build fixed-width 10-bin histogram over finite distances
                    std::vector<double> vals;
                    vals.reserve(gd.node_ids.size());
                    for (size_t i = 0; i < gd.node_ids.size(); ++i) {
                        double d = globalD[i];
                        if (std::isfinite(d)) vals.push_back(d);
                    }
                    if (!vals.empty()) {
                        double minv = vals[0], maxv = vals[0];
                        for (double v : vals) { if (v < minv) minv = v; if (v > maxv) maxv = v; }
                        int buckets = 10;
                        std::vector<long> counts(buckets, 0);
                        if (maxv == minv) {
                            // all zero or same value: put all into last bin
                            counts[buckets-1] = static_cast<long>(vals.size());
                        } else {
                            double width = (maxv - minv) / buckets;
                            for (double v : vals) {
                                int b = static_cast<int>(std::floor((v - minv) / width));
                                if (b >= buckets) b = buckets - 1;
                                if (b < 0) b = 0;
                                counts[b]++;
                            }
                        }
                        std::ostringstream hj;
                        hj << "{\"bins\":[";
                        double width = (maxv == minv ? 1.0 : (maxv - minv) / buckets);
                        for (int i = 0; i < buckets; ++i) {
                            if (i > 0) hj << ",";
                            double le = minv + width * (i + 1);
                            hj << "{\"le\":" << std::setprecision(15) << le << ",\"count\":" << counts[i] << "}";
                        }
                        hj << "],\"min\":" << std::setprecision(15) << minv
                           << ",\"max\":" << std::setprecision(15) << maxv
                           << ",\"total\":" << vals.size()
                           << ",\"bucket_scheme\":\"fixed_width\",\"bucket_count\":" << buckets << "}";
                        histogram_json = hj.str();
                    } else {
                        histogram_json.clear();
                    }

                    // Expose iterations/messages/bytes from local counters
                    iterations = iters;
                    messages = msg;
                    bytes = by;

                    if (args.verbose) {
                        std::cout << "[dijkstra] finished: iters=" << iterations
                                  << ", messages=" << messages
                                  << ", bytes=" << bytes << std::endl;
                    }
                }
            }
            rank_log(args.logDir, world_rank, "dijkstra", "Finished distributed Dijkstra (global-min baseline)");
        } catch (const std::exception& ex) {
            if (world_rank == 0) std::cerr << "Dijkstra failed: " << ex.what() << std::endl;
            MPI_Abort(MPI_COMM_WORLD, 7);
        }
    } else {
        if (world_rank == 0) {
            std::cerr << "Unknown algo: " << args.algo << std::endl;
        }
        MPI_Abort(MPI_COMM_WORLD, 2);
    }

    // Timing end and summaries (rank 0)
    auto t1 = std::chrono::steady_clock::now();
    long long runtime_ms = std::chrono::duration_cast<std::chrono::milliseconds>(t1 - t0).count();
    std::string end_str = now_iso8601();
    std::string seed = read_seed_from_graph_manifest();

    if (world_rank == 0) {
        const std::string algo_name = args.algo;
        const std::string hist = (algo_name == "dijkstra" ? histogram_json : std::string());
        write_summary_json(algo_name, args, world_size, iterations, messages, bytes, runtime_ms, start_str, end_str, seed, summary_extra_json, hist);
        write_run_manifest(algo_name, args, world_size, start_str, end_str, runtime_ms, seed);
    }

    MPI_Finalize();
    return 0;
}
