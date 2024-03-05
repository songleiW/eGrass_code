# eGrass: An Encrypted Attributed Subgraph Matching System with Malicious Security

**WARNING**: This is an academic proof-of-concept prototype and has not received careful code review. This implementation is NOT ready for production use.

This prototype is released under the Apache v2 license (see [License](#license)).

## Setup

Install gRPC (tested on v1.48.1) using the instructions [here](https://grpc.io/docs/languages/cpp/quickstart/).

Download the [Boost](https://www.boost.org/) library (tested on versions 1.74-1.76; can be installed on Ubuntu with `sudo apt install libboost-all-dev`) and [Relic](https://github.com/relic-toolkit/relic) (tested on version 0.6.0; no presets needed while building Relic; use `-DMULTI=OPENMP` flag with `cmake` when building Relic).

To install the dependencies to run benchmarking scripts, `cd scripts` and run `pip install -r requirements.txt`.

Note that the [libPSI](https://github.com/osu-crypto/libPSI) and [libOTe](https://github.com/osu-crypto/libOTe) libraries, which build on [cryptoTools](https://github.com/ladnir/cryptoTools/tree/master), are already included in `fss-core`.

## Building

This project requires an NVIDIA GPU, and assumes you have your GPU drivers and the [NVIDIA CUDA Toolkit](https://docs.nvidia.com/cuda/) already installed. The following has been tested with the `Deep Learning Base AMI (Ubuntu 20.04.3) Version 53.5` AMI.

Checkout external modules
```
git submodule update --init --recursive
```
uild CUTLASS

```
cd ext/cutlass
mkdir build
cmake .. -DCUTLASS_NVCC_ARCHS=<YOUR_GPU_ARCH_HERE> -DCMAKE_CUDA_COMPILER_WORKS=1 -DCMAKE_CUDA_COMPILER=<YOUR NVCC PATH HERE>
make -j

Build libOTe 
```
cd PredEval/libOTe
cmake . -DENABLE_RELIC=ON -DENABLE_NP=ON -DENABLE_KKRT=ON
make -j
```
Build libPSI
```
cd PredEval/libPSI
cmake . -DENABLE_RELIC=ON -DENABLE_DRRN_PSI=ON -DENABLE_KKRT_PSI=ON
make -j
```

Build networking code
```
cd network
cmake .
make
cd ..
```

## Testing locally

To run the entire system locally, start server X as `./build/bin/query_server config/serverX.config`. Start the client with `./build/bin/bench config/client.config`.
Alternatively, start the client with `./build/bin/correctness_tests` to run the correctness tests. Modify the parameters in the corresponding config files to run with different settings (e.g. number of cores, malicious security).
Make sure to start the servers within 10 seconds of each other and wait until each has printed "DONE WITH SETUP" before starting the client (this means initialization has completed).

## Limitations

The rollup functionality suggested as an extension for the construction in the
paper is not fully implemented. Also, the node values  are directly
returned without aggregating by the user-defined aggregation function.
