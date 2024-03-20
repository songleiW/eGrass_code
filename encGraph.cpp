#include "encGraph.h"
#include <iostream>
#include <vector>
#define MAX 2147483647 // sys.maxsize
#define NL 13673453 // Number of edges
#define NV 107614 // Number of Vertices
#define n_parties 3 // Number of parties
#define n_values MAX // Number of possible values for each private value


std::vector<std::vector<int>> convertToKAutomorphic(const std::vector<std::vector<int>>& graph, int k) {
    std::vector<std::vector<int>> kAutomorphicGraph;

    for (const auto& node : graph) {
        std::vector<int> newNode(node.begin(), node.end());
        kAutomorphicGraph.push_back(newNode);
    }

    int originalNodeCount = graph.size();
    for (int i = 0; i < k - 1; ++i) {
        std::vector<int> dummyNode;
        for (int j = 0; j < originalNodeCount; ++j) {
            dummyNode.push_back(originalNodeCount + i * originalNodeCount + j);
        }
        kAutomorphicGraph.push_back(dummyNode);
    }

    for (int i = 0; i < originalNodeCount; ++i) {
        for (int j = 1; j < k; ++j) {
            for (int l = 0; l < originalNodeCount; ++l) {
                kAutomorphicGraph[i].push_back(originalNodeCount + (j - 1) * originalNodeCount + l);
            }
        }
    }

    return kAutomorphicGraph;
}





std::vector<int> encode(int value) {
    std::vector<int> one_hot(n_values, 0);
    one_hot[value] = 1;
    return one_hot;
}

std::vector<std::vector<int>> streaming_graph_values(10, std::vector<int>(10));

std::vector<std::vector<std::vector<std::vector<int>>>> streaming_graph_encrypted(n_parties, std::vector<std::vector<std::vector<int>>>(10, std::vector<std::vector<int>>(10, std::vector<int>(n_values))));

void encryptGraph(Graph) {

    srand(time(0));

    for (int i = 0; i < NV; ++i) {
        for (int j = 0; j < NL; ++j) {
            value = Graph[i][j];
            graph_values[i][j][1] = rand();
            graph_values[i][j][2] = rand();
            graph_values[i][j][3] = value-graph_values[i][j][1]-graph_values[i][j][2];



            for (int party_id = 0; party_id < n_parties; ++party_id) {
                std::vector<int> one_hot_encoding = encode(value);

                for (int k = 0; k < NL; ++k) {
                    int party_share = rand() % 2;
                    graph_encrypted[party_id][i][j][k] = party_share;
                }
            }
        }
    }
}
