cmake_minimum_required(VERSION 3.16)
project(ngs_mpi LANGUAGES CXX)

# C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Build types
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

# Warnings (GCC/Clang)
if (CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
  add_compile_options(-Wall -Wextra -Wpedantic)
endif()

# MPI
find_package(MPI REQUIRED)
message(STATUS "MPI CXX compile flags: ${MPI_CXX_COMPILE_OPTIONS} ${MPI_CXX_COMPILE_DEFINITIONS}")
message(STATUS "MPI CXX include path: ${MPI_CXX_INCLUDE_DIRS}")

# Require vendored json header to be present in the repository (no auto-download)
set(VENDORED_JSON_DIR ${CMAKE_CURRENT_SOURCE_DIR}/include/json_header/nlohmann)
set(VENDORED_JSON ${VENDORED_JSON_DIR}/json.hpp)
if (EXISTS ${VENDORED_JSON})
  message(STATUS "Found vendored nlohmann/json.hpp at: ${VENDORED_JSON}")
else()
  message(FATAL_ERROR "Vendored nlohmann/json.hpp not found at: ${VENDORED_JSON}. Please add it to the repo as agreed.")
endif()

add_executable(ngs_mpi src/main.cpp src/loaders.cpp)

target_include_directories(ngs_mpi
  PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${MPI_CXX_INCLUDE_DIRS}
)

# Link MPI
if (TARGET MPI::MPI_CXX)
  target_link_libraries(ngs_mpi PRIVATE MPI::MPI_CXX)
else()
  target_link_libraries(ngs_mpi PRIVATE ${MPI_CXX_LIBRARIES})
endif()

# For MSVC (unlikely in WSL), ensure secure functions
if (MSVC)
  target_compile_definitions(ngs_mpi PRIVATE _CRT_SECURE_NO_WARNINGS)
endif()
