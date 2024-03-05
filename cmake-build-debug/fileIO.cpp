#include <iostream>
#include <fstream>
#include <vector>
#include <set>
#include <tuple>
#include <algorithm>
#include <unordered_map>
#include <iterator>
#include <cstdlib>
#include <Eigen/Sparse>

using namespace std;
using namespace Eigen;

SparseMatrix<double> readFile(int flag) {
    string fileName;
    int N;
    if (flag == 1) {
        fileName = "Dataset/Gplus.txt";
        N = 102100;
    }

    ifstream file(fileName);
    string line;
    vector<pair<int, int>> data;

    while (getline(file, line)) {
        istringstream iss(line);
        int index1, index2;
        if (!(iss >> index1 >> index2)) {
            break;
        }
        data.push_back(make_pair(index1, index2));
        data.push_back(make_pair(index2, index1));
    }
    file.close();

    // 去除重复的数据
    set<pair<int, int>> dataSet(data.begin(), data.end());
    data.assign(dataSet.begin(), dataSet.end());

    // 提取行列数据
    vector<int> row(data.size()), col(data.size());
    vector<double> ele(data.size(), 1.0);
    for (size_t i = 0; i < data.size(); ++i) {
        row[i] = data[i].first;
        col[i] = data[i].second;
    }

    // 创建稀疏矩阵
    SparseMatrix<double> A(N, N);
    vector<Triplet<double>> tripletList;
    for (size_t i = 0; i < data.size(); ++i) {
        tripletList.push_back(Triplet<double>(row[i], col[i], ele[i]));
    }
    A.setFromTriplets(tripletList.begin(), tripletList.end());

    // 设置对角线元素为1
    for (int i = 0; i < N; ++i) {
        A.coeffRef(i, i) = 1.0;
    }

    return A;
}

