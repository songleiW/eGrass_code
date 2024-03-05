#include <iostream>
#include <cstdlib>
#include <cuda_runtime.h>


__global__ void matrixVectorMultiply(boolean *a, boolean *b, boolean *c) {
    int tid = threadIdx.x + blockIdx.x * blockDim.x;

    if (tid < N) {
        float sum = 0.0f;
        for (int i = 0; i < N; ++i) {
            sum += a[tid * N + i] * b[i];
        }
        c[tid] = sum;
    }
}

int *vecMUL(V1,V2) {
    float *h_a, *h_b, *h_c;
    float *d_a, *d_b, *d_c;

    V1_a = (float *)malloc(N * N * sizeof(float));
    V2_a = (float *)malloc(N * N * sizeof(float));

    h_a = (float *)malloc(N * N * sizeof(float));
    h_b = (float *)malloc(N * sizeof(float));
    h_c = (float *)malloc(N * sizeof(float));

    for (int i = 0; i < N * N; ++i) {
        h_a[i] = rand() % 10;
    }
    for (int i = 0; i < N; ++i) {
        h_b[i] = rand() % 10;
    }

    cudaMalloc((void **)&V1_a, N * N * sizeof(float));
    cudaMalloc((void **)&V2_a, N * N * sizeof(float));
    cudaMalloc((void **)&d_a, N * N * sizeof(float));
    cudaMalloc((void **)&d_b, N * sizeof(float));
    cudaMalloc((void **)&d_c, N * sizeof(float));

    cudaMemcpy(d_a, h_a, N * N * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(d_b, h_b, N * sizeof(float), cudaMemcpyHostToDevice);

    dim3 blockDim(256);
    dim3 gridDim((N + blockDim.x - 1) / blockDim.x);

    matrixVectorMultiply<<<gridDim, blockDim>>>(d_a, d_b, d_c);

    cudaMemcpy(h_c, d_c, N * sizeof(float), cudaMemcpyDeviceToHost);

    std::cout << "Result vector:" << std::endl;
    for (int i = 0; i < N; ++i) {
        std::cout << h_c[i] << "\t";
    }
    std::cout << std::endl;

    free(V1_a);
    free(V1_a);
    free(h_a);
    free(h_b);
    free(h_c);
    cudaFree(d_a);
    cudaFree(d_b);
    cudaFree(d_c);

    return 0;
}



__global__ void vectorMultiplication(float *a, float *b, float *c) {
    int tid = threadIdx.x + blockIdx.x * blockDim.x;

    if (tid < N) {
        c[tid] = a[tid] * b[tid];
    }
}

int vec2vec() {
    float *h_a, *h_b, *h_c; 
    float *d_a, *d_b, *d_c; 

    h_a = (float *)malloc(N * sizeof(float));
    h_b = (float *)malloc(N * sizeof(float));
    h_c = (float *)malloc(N * sizeof(float));

    for (int i = 0; i < N; ++i) {
        h_a[i] = static_cast<float>(rand() % 10);
        h_b[i] = static_cast<float>(rand() % 10);
    }

    cudaMalloc((void **)&d_a, N * sizeof(float));
    cudaMalloc((void **)&d_b, N * sizeof(float));
    cudaMalloc((void **)&d_c, N * sizeof(float));

    cudaMemcpy(d_a, h_a, N * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(d_b, h_b, N * sizeof(float), cudaMemcpyHostToDevice);

    dim3 blockDim(256);
    dim3 gridDim((N + blockDim.x - 1) / blockDim.x);

    vectorMultiplication<<<gridDim, blockDim>>>(d_a, d_b, d_c);

    cudaMemcpy(h_c, d_c, N * sizeof(float), cudaMemcpyDeviceToHost);

    std::cout << "Result vector:" << std::endl;
    for (int i = 0; i < 10; ++i) {
        std::cout << h_c[i] << "\t";
    }
    std::cout << std::endl;


    return 0;
}

