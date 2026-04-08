#include <mpi.h>
#include <iostream>
#include <string>
#include <vector>

// Include path will be: mpi_runtime/include/json_header/nlohmann/json.hpp
// Added later when loaders are implemented.
// #include <json_header/nlohmann/json.hpp>

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

    // Stub: algorithms to be implemented next phases.
    if (args.algo == "leader") {
        if (world_rank == 0) {
            std::cout << "[stub] Leader election will run here." << std::endl;
        }
    } else if (args.algo == "dijkstra") {
        if (world_rank == 0) {
            std::cout << "[stub] Distributed Dijkstra will run here." << std::endl;
        }
    } else {
        if (world_rank == 0) {
            std::cerr << "Unknown algo: " << args.algo << std::endl;
        }
        MPI_Abort(MPI_COMM_WORLD, 2);
    }

    MPI_Barrier(MPI_COMM_WORLD);

    if (world_rank == 0) {
        std::cout << "ngs_mpi finished (stub)." << std::endl;
    }

    MPI_Finalize();
    return 0;
}
