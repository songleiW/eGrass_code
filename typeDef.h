#ifndef FSSCODE_TYPEDEF_H
#define FSSCODE_TYPEDEF_H
using namespace std;
#include "bitset"
#include "stdlib.h"
#include <vector>
#include "ctime"
#include "math.h"
#define LAMBDA  128
#define N 18 //18 20万  20 100万
struct DPFKey{
    bitset<LAMBDA> s;
    vector<bitset<LAMBDA>> CWs;
    vector<bool> CWtR,CWtL;
    bool CWout;
};
#endif //FSSCODE_TYPEDEF_H