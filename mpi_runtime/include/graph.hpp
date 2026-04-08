#pragma once
#include <string>
#include <vector>
#include <unordered_map>
#include <limits>

// Lightweight graph structures for MPI runtime

struct Edge {
    int from = -1;
    int to = -1;
    double cost = 1.0; // must be >= 0
};

struct GraphData {
    int num_nodes = 0;                    // expected to be max_id+1 if ids are dense [0..N-1]
    std::vector<int> node_ids;            // explicit ids as present in JSON
    std::vector<Edge> edges;              // all directed edges
    // Adjacency (filled post-parse for convenience)
    std::vector<std::vector<Edge>> adj;   // size = num_nodes if ids dense; otherwise indexed via id_to_idx
    std::unordered_map<int,int> id_to_idx; // map node id -> local contiguous index
    bool ids_dense_0_to_n_minus_1 = false;
};

// Partition description loaded from partition JSON
struct PartitionData {
    int ranks = 0;
    int total_nodes = 0;
    int cross_edges = 0;
    // owner of node id
    std::unordered_map<int,int> owner_of; // node id -> rank
    // per-rank owned nodes and ghosts as provided
    std::unordered_map<int, std::vector<int>> per_rank_nodes; // rank -> node ids
    std::unordered_map<int, std::vector<int>> per_rank_ghosts; // rank -> node ids
};

// Per-rank view derived from GraphData + PartitionData
struct RankView {
    int world_rank = 0;
    int world_size = 1;
    // owned nodes
    std::vector<int> owned_nodes; // node ids
    // quick membership test for owned
    std::unordered_map<int, bool> is_owned;
    // adjacency for owned nodes only
    std::unordered_map<int, std::vector<Edge>> owned_adj; // id -> outgoing edges (may target remote owners)
    // ghost nodes referenced by cross edges
    std::vector<int> ghosts; // node ids
};

// Loaders (implemented in src/loaders.cpp)
GraphData load_two_line_graph_json(const std::string& path);
PartitionData load_partition_json(const std::string& path);

// Build the per-rank view from parsed inputs
RankView build_rank_view(const GraphData& g, const PartitionData& p, int world_rank, int world_size);
