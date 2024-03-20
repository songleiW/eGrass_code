#include <string>
#include <vector>
#include "../core/client.h"
#include "../core/query.h"
#include "../../secure-indices/core/common.h"

using grpc::Channel;

using namespace dorydb;
using namespace std;

bool malicious = true;
uint8_t mac_factor = (malicious)? 2 : 1;

bool dpfAggTest(QueryClient *client, int numConds) {
    QueryObj q;
    q.agg_table_id = "test_vals";
    vector<Condition> conds;
    for (int i = 0; i < numConds; i++) {
        Condition cond;
        cond.table_id = "test_dpf";
        cond.x = 1;
        cond.cond_type = POINT_COND;
        conds.push_back(cond);
    }
    Expression expr;
    expr.op_type = numConds == 1 ? NO_OP : AND_OP;
    vector<Expression> emptyExprs;
    expr.exprs = emptyExprs;
    expr.conds = conds;
    q.expr = &expr;

    uint32_t numBuckets = 16;
    uint32_t windowSize = 16;;
    vector<uint128_t> dataVals(windowSize, (uint128_t)1);
    vector<uint32_t> dcfVals(windowSize, (uint32_t)1);

    client->AddValList(string("test_vals"), windowSize, dataVals);
    client->AddDPFTable(string("test_dpf"), windowSize, numBuckets, dcfVals);

    uint128_t agg = client->AggQuery(q.agg_table_id, q);

    if (agg == numBuckets) {
        return true;
    }
    return false;
}

bool dcfAggTest(QueryClient *client, int numConds) {
    QueryObj q;
    q.agg_table_id = "test_vals";
    vector<Condition> conds;
    for (int i = 0; i < numConds; i++) {
        Condition cond;
        cond.table_id = "test_dcf";
        cond.cond_type = RANGE_COND;
        cond.left_x = 8;
        cond.right_x = 4;
        conds.push_back(cond);
    }
    Expression expr;
    expr.op_type = numConds == 1 ? NO_OP : AND_OP;
    vector<Expression> emptyExprs;
    expr.exprs = emptyExprs;
    expr.conds = conds;
    q.expr = &expr;

    uint32_t numBuckets = 16;
    uint32_t windowSize = 16;;
    vector<uint128_t> dataVals(windowSize, (uint128_t)1);
    vector<uint32_t> dcfVals(windowSize, (uint32_t)1);
    for (int i = 0; i < windowSize; i++) {
        dcfVals[i] = i % numBuckets;
    }

    client->AddValList(string("test_vals"), windowSize, dataVals);
    client->AddDCFTable(string("test_dcf"), windowSize, numBuckets, dcfVals);

    uint128_t agg = client->AggQuery(q.agg_table_id, q);
    cout << "Aggregate retrieved: " << agg << endl;

    if (agg == 3) {
        return true;
    }
    return false;
}

bool aggTreeTest(QueryClient *client) {
    map<uint64_t, uint128_t> aggTreeData;
    int depth = 8;
    int left_x = 8;
    int right_x = 8;
    string table_id = "test_aggtree";
    for (uint64_t i = 1; i < (1 << (depth - 1)); i++) {
        uint128_t one = 1;
        aggTreeData[i+1] = one;
    }

    client->AddAggTree(table_id, sum, depth, aggTreeData);
    uint128_t *ret;
    uint128_t *ret_r;
    client->AggTreeQuery(table_id, left_x, right_x, &ret, &ret_r);
    return true;
}

bool dcfTableTest(QueryClient *client) {
    uint32_t windowSize = 256;
    uint32_t numBuckets = 256;
    string table_id = "test";
    uint32_t left_x = 11;
    uint32_t right_x = 6;
    vector<uint32_t> data(windowSize, 1);
    for (int i = 0; i < windowSize; i++) {
        data.push_back(rand() % numBuckets);
    }
    client->AddDCFTable(table_id, windowSize, numBuckets, data);
    uint128_t *ret = client->DCFQuery(table_id, left_x, right_x, mac_factor * windowSize);
    uint128_t *ret_r = ret + (mac_factor)*windowSize;
    uint128_t alpha = client->GetMACAlpha();

   bool correct = true;
    for (int i = 0; i < windowSize; i++) {
        if ((data[i] >= left_x || data[i] <= right_x) && ret[i] == 1) {
            correct = false;
        } else if ((data[i] < left_x && data[i] > right_x) && ret[i] != 1) {
            correct = false;
        }
    }
    if(malicious){
        for (int i = 0; i < windowSize; i++){
            if (ret[i + windowSize] != (alpha * ret[i])){
                correct = false;
            }
        }
    }

    if (correct) {
    }

    return correct;
 
}

int main(int argc, char *argv[]) {
    string mal_on = (malicious) ? "ON" : "OFF";
    string addrs[3] = { "127.0.0.1:12345", "127.0.0.1:12346", "127.0.0.1:12347" };
    vector<shared_ptr<grpc::Channel>> channels;
    for (int i = 0; i < NUM_SERVERS; i++) {
        shared_ptr<grpc::Channel> channel = grpc::CreateChannel(addrs[i], grpc::InsecureChannelCredentials());
        channels.push_back(channel);
    }
    QueryClient *client = new QueryClient(channels, malicious);

    bool correct = dcfTableTest(client);
    correct = correct && aggTreeTest(client);
    correct = correct && dpfAggTest(client, 1);
    correct = correct && dpfAggTest(client, 5);
    correct = correct && dcfAggTest(client, 1);
    correct = correct && dcfAggTest(client, 5);

}
