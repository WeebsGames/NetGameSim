#include <mpi.h>
#include <iostream>
#include <string>
#include <vector>
#include <fstream>
#include <sstream>
#include <chrono>
#include <iomanip>
#include <filesystem>

#include "../include/graph.hpp"

namespace fs = std::filesystem;

struct CmdArgs {
    std::string graphPath;
    std::string partPath;
    std::string algo; // leader | dijkstra
    int rounds = 0;   // optional for leader
    int source = 0;   // for dijkstra
    std::string logDir = "outputs/";
    bool verbose = false;
};

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
                               const std::string& end_time) {
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
    os << "  \"args\": { \"rounds\": " << args.rounds << ", \"source\": " << args.source << ", \"verbose\": " << (args.verbose?1:0) << " }\n";
    os << "}\n";
}

int main(int argc, char** argv) {
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

            // TODO: Implement distributed Dijkstra core loop here (global min selection, relaxations).
            // For now, leave counters at zero to validate loaders and logging path.
            iterations = 0; messages = 0; bytes = 0;
        } catch (const std::exception& ex) {
            if (world_rank == 0) std::cerr << "Dijkstra setup failed: " << ex.what() << std::endl;
            MPI_Abort(MPI_COMM_WORLD, 4);
        }
    } else {
        if (world_rank == 0) {
            std::cerr << "Unknown algo: " << args.algo << std::endl;
        }
        MPI_Abort(MPI_COMM_WORLD, 2);
    }

    MPI_Barrier(MPI_COMM_WORLD);

    auto t1 = std::chrono::steady_clock::now();
    auto runtime_ms = std::chrono::duration_cast<std::chrono::milliseconds>(t1 - t0).count();
    std::string end_str = now_iso8601();

    if (world_rank == 0) {
        write_summary_json(args.algo, args, world_size, iterations, messages, bytes, runtime_ms, start_str, end_str);
        std::cout << "ngs_mpi finished (" << args.algo << ") in " << runtime_ms << " ms" << std::endl;
    }

    MPI_Finalize();
    return 0;
}
