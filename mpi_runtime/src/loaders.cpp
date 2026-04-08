#include "../include/graph.hpp"
#include <fstream>
#include <sstream>
#include <stdexcept>
#include <algorithm>
#include <set>
#include <cctype>

#include <json_header/nlohmann/json.hpp>

using nlohmann::json;

static std::string trim(const std::string& s) {
    auto b = s.begin();
    while (b != s.end() && std::isspace(static_cast<unsigned char>(*b))) ++b;
    auto e = s.end();
    do { if (e==s.begin()) break; --e; } while (std::isspace(static_cast<unsigned char>(*e)) && e!=s.begin());
    if (b==s.end()) return "";
    return std::string(b, e+1);
}

GraphData load_two_line_graph_json(const std::string& path) {
    std::ifstream is(path);
    if (!is) throw std::runtime_error("Failed to open graph file: " + path);

    std::string nodes_line; std::string edges_line;
    std::getline(is, nodes_line);
    std::getline(is, edges_line);
    nodes_line = trim(nodes_line);
    edges_line = trim(edges_line);
    if (nodes_line.empty() || edges_line.empty()) {
        throw std::runtime_error("Graph JSON must contain two non-empty lines: nodes then edges");
    }

    json jnodes = json::parse(nodes_line);
    json jedges = json::parse(edges_line);

    if (!jnodes.is_array() || !jedges.is_array()) {
        throw std::runtime_error("Graph JSON lines must be arrays");
    }

    GraphData gd;
    gd.node_ids.reserve(jnodes.size());
    std::set<int> idset;
    int max_id = -1;
    for (const auto& n : jnodes) {
        if (!n.is_object() || !n.contains("id")) {
            throw std::runtime_error("Each node object must contain an 'id'");
        }
        int id = n.at("id").get<int>();
        gd.node_ids.push_back(id);
        idset.insert(id);
        if (id > max_id) max_id = id;
    }
    gd.num_nodes = static_cast<int>(gd.node_ids.size());
    gd.ids_dense_0_to_n_minus_1 = (max_id + 1 == gd.num_nodes);

    gd.edges.reserve(jedges.size());
    for (const auto& e : jedges) {
        Edge ed;
        if (e.contains("fromNode") && e.at("fromNode").is_object()) {
            ed.from = e.at("fromNode").at("id").get<int>();
        } else if (e.contains("from")) {
            ed.from = e.at("from").get<int>();
        } else if (e.contains("u")) {
            ed.from = e.at("u").get<int>();
        } else {
            throw std::runtime_error("Edge missing from/fromNode/u id");
        }
        if (e.contains("toNode") && e.at("toNode").is_object()) {
            ed.to = e.at("toNode").at("id").get<int>();
        } else if (e.contains("to")) {
            ed.to = e.at("to").get<int>();
        } else if (e.contains("v")) {
            ed.to = e.at("v").get<int>();
        } else {
            throw std::runtime_error("Edge missing to/toNode/v id");
        }
        if (e.contains("cost")) {
            ed.cost = e.at("cost").get<double>();
        } else {
            // default positive edge weight if absent
            ed.cost = 1.0;
        }
        if (ed.cost < 0) {
            throw std::runtime_error("Edge cost must be nonnegative for Dijkstra");
        }
        gd.edges.push_back(ed);
    }

    // Build id_to_idx and adjacency
    int idx = 0;
    for (int id : gd.node_ids) {
        gd.id_to_idx[id] = idx++;
    }
    gd.adj.assign(gd.node_ids.size(), {});
    for (const auto& e : gd.edges) {
        auto it = gd.id_to_idx.find(e.from);
        if (it == gd.id_to_idx.end()) continue; // ignore malformed
        gd.adj[it->second].push_back(e);
    }

    return gd;
}

PartitionData load_partition_json(const std::string& path) {
    std::ifstream is(path);
    if (!is) throw std::runtime_error("Failed to open partition file: " + path);
    json jp;
    is >> jp;

    PartitionData pd;
    if (!jp.contains("meta")) throw std::runtime_error("Partition JSON missing 'meta'");
    const auto& meta = jp.at("meta");
    pd.ranks = meta.value("ranks", 0);
    pd.total_nodes = meta.value("nodes", 0);
    pd.cross_edges = meta.value("cross_edges", 0);

    if (!jp.contains("owners") || !jp.at("owners").is_object()) {
        throw std::runtime_error("Partition JSON missing 'owners' map");
    }
    for (auto it = jp.at("owners").begin(); it != jp.at("owners").end(); ++it) {
        int nid = std::stoi(it.key());
        int r = it.value().get<int>();
        pd.owner_of[nid] = r;
    }

    if (!jp.contains("per_rank") || !jp.at("per_rank").is_object()) {
        throw std::runtime_error("Partition JSON missing 'per_rank'");
    }
    for (auto it = jp.at("per_rank").begin(); it != jp.at("per_rank").end(); ++it) {
        int r = std::stoi(it.key());
        const auto& ent = it.value();
        if (ent.contains("nodes") && ent.at("nodes").is_array()) {
            for (const auto& v : ent.at("nodes")) pd.per_rank_nodes[r].push_back(v.get<int>());
        }
        if (ent.contains("ghosts") && ent.at("ghosts").is_array()) {
            for (const auto& v : ent.at("ghosts")) pd.per_rank_ghosts[r].push_back(v.get<int>());
        }
    }

    return pd;
}

RankView build_rank_view(const GraphData& g, const PartitionData& p, int world_rank, int world_size) {
    (void)world_size; // currently unused but kept for validation/extensions
    RankView rv;
    rv.world_rank = world_rank;
    rv.world_size = world_size;

    // owned nodes taken from per_rank if present; fallback: derive from owner_of
    auto it_nodes = p.per_rank_nodes.find(world_rank);
    if (it_nodes != p.per_rank_nodes.end()) {
        rv.owned_nodes = it_nodes->second;
    } else {
        for (auto& kv : p.owner_of) if (kv.second == world_rank) rv.owned_nodes.push_back(kv.first);
    }

    for (int id : rv.owned_nodes) rv.is_owned[id] = true;

    // ghosts if any provided
    auto it_ghosts = p.per_rank_ghosts.find(world_rank);
    if (it_ghosts != p.per_rank_ghosts.end()) rv.ghosts = it_ghosts->second;

    // Build owned adjacency
    for (int owned_id : rv.owned_nodes) {
        auto it_idx = g.id_to_idx.find(owned_id);
        if (it_idx == g.id_to_idx.end()) continue; // unknown id
        int li = it_idx->second;
        if (li >= 0 && li < static_cast<int>(g.adj.size())) {
            rv.owned_adj[owned_id] = g.adj[li];
        }
    }

    return rv;
}
