cmake_minimum_required(VERSION 3.16)
project(eGrass_code CUDA)

set(CMAKE_CUDA_STANDARD 14)

add_executable(eGrass_code main.cu
        vecMul.cpp
        vecMul.h
        PredEval/DCF-source/DCFServer.cpp
        PredEval/DCF-source/DCFClient.cpp
        util.cpp
        util.h
        encGraph.cpp
        encGraph.h
        correctness_tests.cpp
        fileIO.h
        fileIO.cpp)

set_target_properties(eGrass_code PROPERTIES
        CUDA_SEPARABLE_COMPILATION ON)
