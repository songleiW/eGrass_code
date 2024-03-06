#include "fileIO.h"
#include <iostream>
#include <fstream>
#include <vector>
#include <set>
#include <algorithm>
#include <Eigen/Sparse>
using namespace std;
using namespace Eigen;

SparseMatrix<double> readFile(int flag) {
    string fileName;
    int N;
    if (flag == 1) {
        fileName = "Dataset/Gplus.txt";
        N = 102100;
    } else {
        cerr << "Invalid flag value" << endl;
        exit(1);
    }

    ifstream file(fileName);
    string line;
    vector<pair<int, int>> data;
    while (getline(file, line)) {
        int index1, index2;
        sscanf(line.c_str(), "%d %d", &index1, &index2);
        data.push_back(make_pair(index1, index2));
        data.push_back(make_pair(index2, index1));
    }
    file.close();

    set<pair<int, int>> dataSet(data.begin(), data.end());
    data.assign(dataSet.begin(), dataSet.end());

    vector<Triplet<double>> triplets;
    for (const auto &entry : data) {
        triplets.push_back(Triplet<double>(entry.first, entry.second, 1.0));
    }

    SparseMatrix<double> A(N, N);
    A.setFromTriplets(triplets.begin(), triplets.end());
    A.diagonal() = VectorXd::Ones(N);

    return A;
}


SparseMatrix<double> readNonFile(int flag) {
    string fileName;
    int N;
    if (flag == 1) {
        fileName = "Dataset/Gplus.txt";
        N = 102100;
    } else {
        cerr << "Invalid flag value" << endl;
        exit(1);
    }

    ifstream file(fileName);
    string line;
    vector<pair<int, int>> data;
    while (getline(file, line)) {
        int index1, index2;
        sscanf(line.c_str(), "%d %d", &index1, &index2);
        data.push_back(make_pair(index1, index2));
    }
    file.close();

    set<pair<int, int>> dataSet(data.begin(), data.end());
    data.assign(dataSet.begin(), dataSet.end());

    vector<Triplet<double>> triplets;
    for (const auto &entry : data) {
        triplets.push_back(Triplet<double>(entry.first, entry.second, 1.0));
    }

    SparseMatrix<double> A(N, N);
    A.setFromTriplets(triplets.begin(), triplets.end());
    A.diagonal() = VectorXd::Ones(N);

    return A;
}


vector<int> readDegree(int flag) {
    string fileName;
    int N;
    if (flag == 1) {
        fileName = "Dataset/Gplus.txt";
        N = 102100;
    } else {
        cerr << "Invalid flag value" << endl;
        exit(1);
    }

    ifstream file(fileName);
    string line;
    vector<int> degree(N, 0);
    while (getline(file, line)) {
        int index1, index2;
        sscanf(line.c_str(), "%d %d", &index1, &index2);
        degree[index1]++;
         if (flag == 1) {
             degree[index2]++;
         }
    }
    file.close();

    return degree;
}


void dealGplus() {
    string fileName = "Dataset/Gplus.txt";
    ifstream file(fileName);
    ofstream newFile("Dataset/newGplus.txt");

    unordered_map<string, string> userID;
    string line;
    int num = 0;
    while (getline(file, line)) {
        num++;
        if (line == "\n") {
            continue;
        }
        size_t pos = line.find(' ');
        string index1 = line.substr(0, pos);
        string index2 = line.substr(pos + 1);
        index1.erase(remove(index1.begin(), index1.end(), ' '), index1.end());
        index2.erase(remove(index2.begin(), index2.end(), ' '), index2.end());

        if (userID.find(index1) == userID.end()) {
            userID[index1] = to_string(userID.size());
        }
        if (userID.find(index2) == userID.end()) {
            userID[index2] = to_string(userID.size());
        }
        newFile << userID[index1] << " " << userID[index2] << "\n";
    }
    file.close();
    newFile.close();
}


