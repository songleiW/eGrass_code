#include <fstream>
#include <thread>
#include <grpcpp/grpcpp.h>
#include <grpcpp/health_check_service_interface.h>
#include <grpcpp/ext/proto_server_reflection_plugin.h>
#include <cryptoTools/Crypto/AES.h>
#include "../../secure-indices/core/DCFTable.h"
#include "../../secure-indices/core/DPFTable.h"
#include "util.h"
#include "SecureShuffle.h"
#include "encGraph.h"
#include "fileIO.h"

using grpc::Server;
using grpc::ServerBuilder;
using grpc::ServerContext;
using grpc::Channel;
using grpc::ClientContext;
using grpc::Status;
using grpc::ServerAsyncResponseWriter;
using grpc::ServerCompletionQueue;
using grpc::ChannelArguments;
using dbquery::Query;
using dbquery::Aggregate;
using dbquery::InitSystemRequest;
using dbquery::InitSystemResponse;
using dbquery::InitDCFRequest;
using dbquery::InitDCFResponse;
using dbquery::InitDPFRequest;
using dbquery::InitDPFResponse;
using dbquery::InitListRequest;
using dbquery::InitListResponse;
using dbquery::InitATRequest;
using dbquery::InitATResponse;
using dbquery::UpdateDCFRequest;
using dbquery::BatchedUpdateDCFRequest;
using dbquery::UpdateDCFResponse;
using dbquery::BatchedUpdateDCFResponse;
using dbquery::UpdateDPFRequest;
using dbquery::BatchedUpdateDPFRequest;
using dbquery::UpdateDPFResponse;
using dbquery::BatchedUpdateDPFResponse;
using dbquery::UpdateListRequest;
using dbquery::BatchedUpdateListRequest;
using dbquery::UpdateListResponse;
using dbquery::BatchedUpdateListResponse;
using dbquery::AppendAT1Request;
using dbquery::AppendAT1Response;
using dbquery::AppendAT2Request;
using dbquery::AppendAT2Response;
using dbquery::QueryDCFRequest;
using dbquery::QueryDCFResponse;
using dbquery::QueryATRequest;
using dbquery::QueryATResponse;
using dbquery::QueryAggRequest;
using dbquery::QueryAggResponse;
using dbquery::MultRequest;
using dbquery::MultResponse;
using dbquery::CombinedFilter;
using dbquery::BaseFilter;

using json = nlohmann::json;

using namespace std;
using namespace osuCrypto;
using namespace emp;

NetIO * emp_io_upstream;
NetIO * emp_io_downstream;

QueryServer::QueryServer(string addrs[], int serverID, int cores, bool malicious) {
    this->serverID = serverID;
    this->malicious = malicious;
    this->cores = cores;
    block seed = toBlock(rand(), rand());
    PRNG prng(seed);
    prfKey0 = prng.get<uint64_t>();
    prfCounter = 0;
    multReceivedShares = NULL;
}

void QueryServer::StartSystemInit(string addrs[]) {
    new CallData(*this, service, cq, INIT);
    sleep(10);

    ChannelArguments args;
    args.SetMaxSendMessageSize(-1);
    args.SetMaxReceiveMessageSize(-1);
    nextServerStub = Query::NewStub(grpc::CreateCustomChannel(addrs[(serverID + 1) % NUM_SERVERS], grpc::InsecureChannelCredentials(), args));
    multStub = Aggregate::NewStub(grpc::CreateCustomChannel(addrs[(serverID + 1) % NUM_SERVERS], grpc::InsecureChannelCredentials(), args));
    cout << "connected to " << addrs[(serverID + 1) % NUM_SERVERS] << endl;

    int emp_port = 32000;

    string next_server_addr = addrs[(serverID + 1) % NUM_SERVERS];
    int psn = next_server_addr.find(":");
    next_server_addr = next_server_addr.substr(0, psn);

    cout << "connected EMP NetIO to " << next_server_addr << endl;

    InitSystemRequest req;
    InitSystemResponse resp;
    ClientContext ctx;
    req.set_key((char *)&prfKey0, sizeof(uint128_t));
    multStub->SendSystemInit(&ctx, req, &resp);
}

void QueryServer::FinishSystemInit(const uint8_t *key) {
    memcpy((uint8_t *)&prfKey1, key, sizeof(uint128_t));
    cout << "----- DONE WITH SETUP ------" << endl;
}

void QueryServer::AddValList(string id, uint32_t windowSize) {
    vector<uint128_t> list1(windowSize, 0);
    vector<uint128_t> list2(windowSize, 0);
    ValLists[id] = make_pair(list1, list2);
    ValListWindowPtrs[id] = 0;
}

void QueryServer::DCFAddTable(string id, uint32_t windowSize, uint32_t numBuckets, bool malicious) {
    DCFTableServer *s1 = new DCFTableServer(id, getDepth(numBuckets), windowSize, cores, malicious);
    DCFTableServer *s2 = new DCFTableServer(id, getDepth(numBuckets), windowSize, cores, malicious);
    DCFTables[id] = make_pair(s1, s2);
    DCFTableWindowPtrs[id] = 0;
}

void QueryServer::DPFAddTable(string id, uint32_t windowSize, uint32_t numBuckets, bool malicious) {
    DPFTableServer *s1 = new DPFTableServer(id, getDepth(numBuckets), windowSize, cores, malicious);
    DPFTableServer *s2 = new DPFTableServer(id, getDepth(numBuckets), windowSize, cores, malicious);
    DPFTables[id] = make_pair(s1, s2);
    DPFTableWindowPtrs[id] = 0;
}

void QueryServer::AggTreeAddIndex(string id, uint32_t depth, AggFunc aggFunc) {
    AggTreeIndexServer *s1 = new AggTreeIndexServer(id, depth, aggFunc, cores, malicious);
    AggTreeIndexServer *s2 = new AggTreeIndexServer(id, depth, aggFunc, cores, malicious);
    AggTrees[id] = make_pair(s1, s2);
}

void QueryServer::DCFUpdate(string id, uint32_t loc, const uint128_t *data0, const uint128_t *data1) {
    if (loc == APPEND_LOC) {
        loc = DCFTableWindowPtrs[id];
        DCFTableWindowPtrs[id]++;
    }
    setTableColumn(DCFTables[id].first->table, loc, data0, DCFTables[id].first->numBuckets);
    setTableColumn(DCFTables[id].second->table, loc, data1, DCFTables[id].second->numBuckets);
}

void QueryServer::DPFUpdate(string id, uint32_t loc, const uint128_t *data0, const uint128_t *data1) {
    if (loc == APPEND_LOC) {
        loc = DPFTableWindowPtrs[id];
        DPFTableWindowPtrs[id]++;
    }
    setTableColumn(DPFTables[id].first->table, loc, data0, DPFTables[id].first->numBuckets);
    setTableColumn(DPFTables[id].second->table, loc, data1, DPFTables[id].second->numBuckets);
}

void QueryServer::ValListUpdate(string id, uint32_t loc, uint128_t val0, uint128_t val1) {
    if (loc == APPEND_LOC) {
        loc = ValListWindowPtrs[id];
        ValListWindowPtrs[id]++;
    }
    ValLists[id].first[loc] = val0;
    ValLists[id].second[loc] = val1;
}


void QueryServer::DCFQuery(uint128_t **res0, uint128_t **res1, string id, const uint8_t *key0, const uint8_t *key1, uint32_t *len) {
    uint64_t gout_bitsize = 125;
    uint128_t one = 1;
    uint128_t group_mod = one << gout_bitsize;

    uint32_t mac_factor = (DCFTables[id].first->malicious)? 2 : 1;

    *res0 = (uint128_t *)malloc(mac_factor * sizeof(uint128_t) * DCFTables[id].first->windowSize);
    *res1 = (uint128_t *)malloc(mac_factor * sizeof(uint128_t) * DCFTables[id].first->windowSize);

    DCFTables[id].first->deserialize_key(key0, true);
    DCFTables[id].second->deserialize_key(key1, false);

    // true is to run IC and evaluate a double-sided range
    DCFTables[id].first->ic_eval_dcf_table(*res0, gout_bitsize, true, group_mod, true, 0);
    DCFTables[id].second->ic_eval_dcf_table(*res1, gout_bitsize, true, group_mod, true, 0);


    *len = mac_factor * DCFTables[id].first->windowSize;
}


void QueryServer::DPFQuery(uint128_t **res0, uint128_t **res1, string id, const uint8_t *key0, const uint8_t *key1, uint32_t *len) {
    uint64_t gout_bitsize = 125;
    uint128_t one = 1;
    uint128_t group_mod = one << gout_bitsize;

    uint32_t mac_factor = (DPFTables[id].first->malicious)? 2 : 1;

    *res0 = (uint128_t *)malloc(mac_factor * sizeof(uint128_t) * DPFTables[id].first->windowSize);
    *res1 = (uint128_t *)malloc(mac_factor * sizeof(uint128_t) * DPFTables[id].first->windowSize);

    DPFTables[id].first->deserialize_key(key0, true);
    DPFTables[id].second->deserialize_key(key1, false);

    DPFTables[id].first->eval_dpf_table(*res0, gout_bitsize, true, group_mod, 0);
    DPFTables[id].second->eval_dpf_table(*res1, gout_bitsize, true, group_mod, 0);

    *len = mac_factor * DPFTables[id].first->windowSize;
}

void QueryServer::DCFQueryRSS(uint128_t **res0, uint128_t **res1, string id, const uint8_t *key0, const uint8_t *key1, uint32_t *len) {
    DCFQuery(res0, res1, id, key0, key1, len);
    throw std::invalid_argument("MAC batch check not implemented");
    RSSReshare(res0, res1, 1, *len, nullptr, nullptr);
}

void QueryServer::DPFQueryRSS(uint128_t **res0, uint128_t **res1, string id, const uint8_t *key0, const uint8_t *key1, uint32_t *len) {
    DPFQuery(res0, res1, id, key0, key1, len);
    throw std::invalid_argument("MAC batch check not implemented");
    RSSReshare(res0, res1, 1, *len, nullptr, nullptr);
}

void QueryServer::RSSReshareInnerLoop(uint128_t *res0, uint128_t *res1, uint32_t numSets, uint32_t len, int idx) {
    for (int j = 0; j < len; j++) {
        res1[j] += res0[j];
        res1[j] += GetNextSecretShareOfZero(idx * numSets + len);
    }
}

void QueryServer::RSSReshareGenRandCoeffs(uint128_t *rand_coeff_shares0, uint128_t *rand_coeff_shares1, uint32_t numSets, uint32_t len, int idx) {
    int val_len = malicious ? len / 2 : len;
    for (int j = 0; j < val_len; j++) {
        GetNextSecretShareOfRandCoeff(rand_coeff_shares0 + j, rand_coeff_shares1 + j, numSets * len + idx * numSets + len);
    }
}

void QueryServer::RSSReshare(uint128_t **res0, uint128_t **res1, uint32_t numSets, uint32_t len, uint128_t* lin_comb_acc, uint128_t* lin_comb_mac_acc) {
    INIT_TIMER;
    START_TIMER;
    uint8_t *sendShares = (uint8_t *)malloc(numSets * len * sizeof(uint128_t));

    uint128_t *rand_coeff_shares0;
    uint128_t *rand_coeff_shares1;
    if(malicious) {
        rand_coeff_shares0 = (uint128_t *)malloc(numSets * len * sizeof(uint128_t));
        rand_coeff_shares1 = (uint128_t *)malloc(numSets * len * sizeof(uint128_t));
    }
    int mac_factor = malicious ? 2 : 1;
    int val_len = malicious ? len / 2 : len;

    vector<thread> workers;
    for (int i = 0; i < numSets; i++) {
        workers.push_back(thread(&QueryServer::RSSReshareInnerLoop, this, res0[i], res1[i], numSets, len, i));
        if(malicious){
            workers.push_back(thread(&QueryServer::RSSReshareGenRandCoeffs, this, rand_coeff_shares0 + (i * val_len), rand_coeff_shares1 + (i * val_len), numSets, len, i));
        }
    }
    for (int i = 0; i < numSets; i++) {
        // Inner loop worker
        workers[mac_factor * i].join();
        if(malicious){
            // Rand coeff gen worker
            workers[(mac_factor * i) + 1].join();
        }
        memcpy(sendShares + (i * len * sizeof(uint128_t)), res1[i], len * sizeof(uint128_t));
    }
    AdjustPRFCounter(mac_factor * numSets * len);
    STOP_TIMER("RSS reshare comp");
    //printf("did all memcpies for rss reshare\n");
#ifndef USE_EMP
    MultRequest req;
    MultResponse resp;
    ClientContext ctx;
    req.set_shares((uint8_t *)sendShares, numSets * sizeof(uint128_t) * len);
    multStub->SendMult(&ctx, req, &resp);
    unique_lock<mutex> lk(multLock);
    if (multReceivedShares == NULL) {
        new CallData(*this, service, cq, MULT);
    }
    while (multReceivedShares == NULL) {
        multCV.wait(lk);
    }
    for (int i = 0; i < numSets; i++) {
        memcpy(res0[i], ((uint8_t *)multReceivedShares) + (i * len * sizeof(uint128_t)), len * sizeof(uint128_t));
    }
    free(multReceivedShares);
#endif
    multReceivedShares = NULL;
    orderCV.notify_one();

    if(malicious){
        // Optimistically proceed, but store random linear combination
        // in accumulator for client to later check that RSSReshare was
        // error-free.
        AddToBatchMACCheck(res0, res1, rand_coeff_shares0, rand_coeff_shares1, numSets, len, lin_comb_acc, lin_comb_mac_acc);
        delete[] rand_coeff_shares0;
        delete[] rand_coeff_shares1;
    }
}

void QueryServer::AddToBatchMACCheck(uint128_t** x0, uint128_t** x1, uint128_t* coeff0, uint128_t* coeff1, uint32_t numSets, uint32_t len, uint128_t* lin_comb_acc, uint128_t* lin_comb_mac_acc) {
    int val_len = malicious ? len / 2 : len;
    for (int ns = 0; ns < numSets; ns++) {
        for (int i = 0; i < val_len; i++) {
            *lin_comb_acc += (x0[ns][i] * coeff0[(ns * val_len) + i]);
            *lin_comb_acc += (x1[ns][i] * coeff0[(ns * val_len) + i]);
            *lin_comb_acc += (x0[ns][i] * coeff1[(ns * val_len) + i]);
        }
        // MAC
        for (int i = 0; i < val_len; i++) {
            *lin_comb_mac_acc += (x0[ns][val_len + i] * coeff0[(ns * val_len) + i]);
            *lin_comb_mac_acc += (x1[ns][val_len + i] * coeff0[(ns * val_len) + i]);
            *lin_comb_mac_acc += (x0[ns][val_len + i] * coeff1[(ns * val_len) + i]);
        }
    }
}

void QueryServer::Query(string id, const uint8_t *key0, const uint8_t *key1, uint128_t *ret, uint128_t *mac, uint128_t *ret_r, uint128_t *mac_r, int* dd) {
    uint64_t gout_bitsize = 125;
    // *ret = 0;
    // *mac = 0;
    uint128_t one = 1;
    uint128_t group_mod = one << gout_bitsize;
    int depth = AggTrees[id].first->depth;
    *dd = depth;
    uint8_t mac_factor = malicious ? 2 : 1;
    uint8_t lr_factor = 2;
    uint128_t *res1 = (uint128_t *)malloc(lr_factor * mac_factor * (depth + 1) * sizeof(uint128_t));
    uint128_t *res_child1 = (uint128_t *)malloc(lr_factor * mac_factor * (depth + 1) * sizeof(uint128_t));
    uint128_t *res2 = (uint128_t *)malloc(lr_factor * mac_factor * (depth + 1) * sizeof(uint128_t));
    uint128_t *res_child2 = (uint128_t *)malloc(lr_factor * mac_factor * (depth + 1) * sizeof(uint128_t));
    memset(res1, 0, lr_factor * mac_factor * (depth + 1) * sizeof(uint128_t));
    memset(res_child1, 0, lr_factor * mac_factor * (depth + 1) * sizeof(uint128_t));
    memset(res2, 0, lr_factor * mac_factor * (depth + 1) * sizeof(uint128_t));
    memset(res_child2, 0, lr_factor * mac_factor * (depth + 1) * sizeof(uint128_t));

    AggTrees[id].first->deserialize_key(key0, true);
    AggTrees[id].second->deserialize_key(key1, false);

    AggTrees[id].first->eval_agg_tree(res1, res_child1, gout_bitsize, true, group_mod, true);
    AggTrees[id].second->eval_agg_tree(res2, res_child2, gout_bitsize, true, group_mod, true);

    uint128_t* res1_r = res1 + mac_factor*(depth + 1);
    uint128_t* res2_r = res2 + mac_factor*(depth + 1);
    uint128_t* res_child1_r = res_child1 + mac_factor*(depth + 1);
    uint128_t* res_child2_r = res_child2 + mac_factor*(depth + 1);
    res1[0] += res2[0];
    res1_r[0] += res2_r[0];
    if (malicious) {
        res1[depth] += res2[depth];
        res1_r[depth] += res2_r[depth];
    }
    for (int d = 1; d < depth; d++) {

        res1[d] -= res_child1[d-1];
        res2[d] -= res_child2[d-1];
        res1_r[d] -= res_child1_r[d-1];
        res2_r[d] -= res_child2_r[d-1];

        res1[d] += res2[d];
        res1_r[d] += res2_r[d];

        if (malicious) {
            res1[d + depth] -= res_child1[d - 1 + depth];
            res2[d + depth] -= res_child2[d - 1 + depth];
            res1_r[d + depth] -= res_child1_r[d - 1 + depth];
            res2_r[d + depth] -= res_child2_r[d - 1 + depth];

            res1[d + depth] += res2[d + depth];
            res1_r[d + depth] += res2_r[d + depth];
        }
    }
    memcpy(ret, res1, ((depth) * sizeof(uint128_t)));
    memcpy(ret_r, res1_r, ((depth) * sizeof(uint128_t)));
    memcpy(mac, ((uint8_t *)res1) + ((depth) * sizeof(uint128_t)), ((depth) * sizeof(uint128_t)));
    memcpy(mac_r, ((uint8_t *)res1_r) + ((depth) * sizeof(uint128_t)), ((depth) * sizeof(uint128_t)));
    /*ret = res1;
    ret_r = res1_r;
    mac = res1 + depth;
    mac_r = res1_r + depth;*/
}

void QueryServer::AndFilters(uint128_t *shares_out0, uint128_t *shares_out1, uint128_t *shares_x0, uint128_t *shares_x1, uint128_t *shares_y0, uint128_t *shares_y1, uint128_t *zero_shares, uint128_t* coeff0, uint128_t* coeff1, int len, uint128_t* lin_comb_acc, uint128_t* lin_comb_mac_acc) {
    Multiply(shares_out0, shares_out1, shares_x0, shares_x1, shares_y0, shares_y1, zero_shares, coeff0, coeff1, len, lin_comb_acc, lin_comb_mac_acc);
}

void QueryServer::OrFilters(uint128_t *shares_out0, uint128_t *shares_out1, uint128_t *shares_x0, uint128_t *shares_x1, uint128_t *shares_y0, uint128_t *shares_y1, uint128_t *zero_shares, uint128_t* coeff0, uint128_t* coeff1, int len, uint128_t* lin_comb_acc, uint128_t* lin_comb_mac_acc) {
    Multiply(shares_out0, shares_out1, shares_x0, shares_x1, shares_y0, shares_y1, zero_shares, coeff0, coeff1, len, lin_comb_acc, lin_comb_mac_acc);
    for (int i = 0; i < len; i++) {
        shares_out0[i] += shares_x0[i] + shares_y0[i];
        shares_out1[i] += shares_x1[i] + shares_y1[i];
    }
}

void QueryServer::Multiply(uint128_t *shares_out0, uint128_t *shares_out1, uint128_t *shares_x0, uint128_t *shares_x1, uint128_t *shares_y0, uint128_t *shares_y1, uint128_t *zero_shares, uint128_t* coeff0, uint128_t* coeff1, int len, uint128_t* lin_comb_acc, uint128_t* lin_comb_mac_acc) {
    int val_len = malicious ? len / 2 : len;
    uint128_t *tmp = (uint128_t *)malloc(2 * val_len * sizeof(uint128_t));
    //INIT_TIMER;
    //START_TIMER;
    for (int i = 0; i < val_len; i++) {
        shares_out1[i] = (shares_x0[i] * shares_y0[i]);
        shares_out1[i] += (shares_x1[i] * shares_y0[i]);
        shares_out1[i] += (shares_x0[i] * shares_y1[i]);
        shares_out1[i] += zero_shares[i];
        tmp[i] = shares_out1[i];
    }
    if (malicious) {
        for (int i = 0; i < val_len; i++) {
            tmp[i + val_len] = (shares_x0[i + val_len] * shares_y0[i]);
            tmp[i + val_len] += (shares_x1[i + val_len] * shares_y0[i]);
            tmp[i + val_len] += (shares_x0[i + val_len] * shares_y1[i]);
            shares_out1[i + val_len] = tmp[i + val_len];
        }
    }
    //STOP_TIMER("Multiplication time FIRST");
    int mac_factor = malicious ? 2 : 1;

#ifndef USE_EMP
    MultRequest req;
    MultResponse resp;
    ClientContext ctx;
    req.set_shares((uint8_t *)tmp, mac_factor * sizeof(uint128_t) * val_len);
    multStub->SendMult(&ctx, req, &resp);
    unique_lock<mutex> lk(multLock);
    while (multReceivedShares == NULL) {
        multCV.wait(lk);
    }
    INIT_TIMER;
    START_TIMER;
    memcpy(shares_out0, multReceivedShares, mac_factor * sizeof(uint128_t) * val_len);
    STOP_TIMER("Multiplication time SECOND");
    free(tmp);
    free(multReceivedShares);

#else
    assert(false);
    // Using EMP NetIO
    uint128_t* multRcvdShares = (uint128_t*)malloc(mac_factor * sizeof(uint128_t) * val_len);
    thread workers[2];
    if(serverID == 0){
        emp_io_downstream->recv_data(multRcvdShares, mac_factor * sizeof(uint128_t) * val_len);
        emp_io_upstream->send_data(tmp, mac_factor * sizeof(uint128_t) * val_len);
    }
    else{
        emp_io_upstream->send_data(tmp, mac_factor * sizeof(uint128_t) * val_len);
        emp_io_downstream->recv_data(multRcvdShares, mac_factor * sizeof(uint128_t) * val_len);
    }
    memcpy(shares_out0, multRcvdShares, sizeof(uint128_t) * val_len);
    if (malicious) {
        for (int i = 0; i < val_len; i++) {
            shares_out0[i + val_len] = 2 * multRcvdShares[i + val_len] - multRcvdShares[i + 2 * val_len];
            shares_out1[i + val_len] = 2 * tmp[i + val_len] - tmp[i + 2 * val_len];
        }
    }
    //STOP_TIMER("Multiplication time SECOND");
    free(tmp);
    delete[] multRcvdShares;
#endif
    multReceivedShares = NULL;
    orderCV.notify_one();
    if(malicious){
        // Optimistically proceed, but store random linear combination
        // in accumulator for client to later check that RSSReshare was
        // error-free.
        AddToBatchMACCheckFromMult(shares_out0, shares_out1, coeff0, coeff1, len, lin_comb_acc, lin_comb_mac_acc);
    }
}

void QueryServer::AddToBatchMACCheckFromMult(uint128_t* x0, uint128_t* x1, uint128_t* coeff0, uint128_t* coeff1, uint32_t len, uint128_t* lin_comb_acc, uint128_t* lin_comb_mac_acc) {
    int val_len = malicious ? len / 2 : len;
    for (int i = 0; i < val_len; i++) {
        *lin_comb_acc += (x0[i] * coeff0[i]);
        *lin_comb_acc += (x1[i] * coeff0[i]);
        *lin_comb_acc += (x0[i] * coeff1[i]);
    }
    // MAC
    for (int i = 0; i < val_len; i++) {
        *lin_comb_mac_acc += (x0[val_len + i] * coeff0[i]);
        *lin_comb_mac_acc += (x1[val_len + i] * coeff0[i]);
        *lin_comb_mac_acc += (x0[val_len + i] * coeff1[i]);
    }
}

inline uint128_t QueryServer::GetNextSecretShareOfZero(int idx) {
    uint128_t res0 = prfFieldElem(prfKey0, prfCounter + idx);
    uint128_t res1 = prfFieldElem(prfKey1, prfCounter + idx);
    return res1 - res0;
}

inline void QueryServer::GetNextSecretShareOfRandCoeff(uint128_t *rand_coeff_shares0, uint128_t* rand_coeff_shares1, int idx) {
    rand_coeff_shares0[0] = prfFieldElem(prfKey0, prfCounter + idx);
    rand_coeff_shares1[0] = prfFieldElem(prfKey1, prfCounter + idx);
}

void QueryServer::AdjustPRFCounter(int amount) {
    prfCounter += amount;
}

void QueryServer::FinishMultiply(const uint128_t *shares, int len) {
    unique_lock<mutex> lk(multLock);
    //multLock.lock();
    if (multReceivedShares != NULL) {
        new CallData(*this, service, cq, MULT);
    }
    while (multReceivedShares != NULL) {
        orderCV.wait(lk);
    }
    multReceivedShares = (uint128_t *)malloc(len);
    memcpy(multReceivedShares, shares, len);
    multCV.notify_one();
}

void QueryServer::FillZeroSharesPlusRandCoeff(uint128_t *zero_shares, uint128_t *rand_coeff_shares0, uint128_t* rand_coeff_shares1, int start_loc, int prf_idx, int chunk_size, int bgn) {
    for (int i = 0; i < chunk_size; i++) {
        zero_shares[i + start_loc] = GetNextSecretShareOfZero(prf_idx + i);
    }
    if(malicious){
        // coeffs are same of MAC part and normal part
        // so only half are needed compared to shares
        // of zero
        for (int i = 0; i < (chunk_size / 2); i++) {
            GetNextSecretShareOfRandCoeff(rand_coeff_shares0 + i + (start_loc/2), rand_coeff_shares1 + i + (start_loc/2), prf_idx + i + bgn);
        }
    }
}

void QueryServer::EvalFilter(uint128_t **filter0, uint128_t **filter1, const CombinedFilter &filterSpec, uint128_t *lin_comb_accumulator, uint128_t *lin_comb_mac_accumulator) {
    *filter0 = NULL;
    *filter1 = NULL;

    // assuming filters all of same type for now
    uint128_t **res0 = (uint128_t **)malloc(sizeof(uint128_t *) * filterSpec.base_filters_size());
    uint128_t **res1 = (uint128_t **)malloc(sizeof(uint128_t *) * filterSpec.base_filters_size());

    *lin_comb_accumulator = 0;
    *lin_comb_mac_accumulator = 0;

    bool is_point = true;
    string baseFilterID;
    uint64_t gout_bitsize = 125;
    uint128_t one = 1;
    uint128_t group_mod = one << gout_bitsize;
    int mac_factor = malicious ? 2 : 1;
    int len;

    for (int i = 0; i < filterSpec.base_filters_size(); i++) {
        BaseFilter baseFilterSpec = filterSpec.base_filters(i);
        baseFilterID = baseFilterSpec.id();
        int windowSize = baseFilterSpec.is_point() ? DPFTables[baseFilterID].first->windowSize : DCFTables[baseFilterID].first->windowSize;
        len = mac_factor * windowSize;

        res0[i] = (uint128_t *)malloc(mac_factor * sizeof(uint128_t) * windowSize);
        res1[i] = (uint128_t *)malloc(mac_factor * sizeof(uint128_t) * windowSize);

        if (baseFilterSpec.is_point()) {
            DPFTables[baseFilterID].first->deserialize_key((const uint8_t *)baseFilterSpec.key0().c_str(), true);
            DPFTables[baseFilterID].second->deserialize_key((const uint8_t *)baseFilterSpec.key1().c_str(), false);
            is_point = true;
        } else {
            DCFTables[baseFilterID].first->deserialize_key((const uint8_t *)baseFilterSpec.key0().c_str(), true);
            DCFTables[baseFilterID].second->deserialize_key((const uint8_t *)baseFilterSpec.key1().c_str(), false);
            is_point = false;
        }
    }

    if (is_point) {
        thread workers[2];
        workers[0] = thread(&dorydb::DPFTableServer::parallel_eval_dpf_table, DPFTables[baseFilterID].first, res0, gout_bitsize, true, group_mod);
        workers[1] = thread(&dorydb::DPFTableServer::parallel_eval_dpf_table, DPFTables[baseFilterID].second, res1, gout_bitsize, true, group_mod);
        workers[0].join();
        workers[1].join();
    } else {
        thread workers[2];
        workers[0] = thread(&dorydb::DCFTableServer::parallel_ic_eval_dcf_table, DCFTables[baseFilterID].first, res0, gout_bitsize, true, group_mod, true);
        workers[1] = thread(&dorydb::DCFTableServer::parallel_ic_eval_dcf_table, DCFTables[baseFilterID].second, res1, gout_bitsize, true, group_mod, true);
        workers[0].join();
        workers[1].join();

    }

    // Convert 3-out-of-3 shares from FSS part to RSS shares
    RSSReshare(res0, res1, filterSpec.base_filters_size(), len, lin_comb_accumulator, lin_comb_mac_accumulator);

    // Generate some random values for zero sharing and random coeffs (for batch MAC check)
    uint128_t **zero_shares = (uint128_t **)malloc(filterSpec.base_filters_size() * sizeof(uint128_t*));
    uint128_t **rand_coeff_shares0 = (uint128_t **)malloc(filterSpec.base_filters_size() * sizeof(uint128_t*));
    uint128_t **rand_coeff_shares1 = (uint128_t **)malloc(filterSpec.base_filters_size() * sizeof(uint128_t*));
    vector<thread>workers;
    int numChunks = 4;
    int chunkSize = len / numChunks;
    INIT_TIMER;
    START_TIMER;
    for (int i = 0; i < filterSpec.base_filters_size(); i++) {
        zero_shares[i] = (uint128_t *)malloc(sizeof(uint128_t) * len);
        if(malicious) {
            rand_coeff_shares0[i] = (uint128_t *)malloc(sizeof(uint128_t) * len);
            rand_coeff_shares1[i] = (uint128_t *)malloc(sizeof(uint128_t) * len);
        }
        for (int j = 0; j < numChunks; j++) {
            workers.push_back(thread(&QueryServer::FillZeroSharesPlusRandCoeff, this, zero_shares[i], rand_coeff_shares0[i], rand_coeff_shares1[i], j * chunkSize, i * len + j * chunkSize, chunkSize, filterSpec.base_filters_size() * len));
        }
    }
    for (int i = 0; i < workers.size(); i++) {
        workers[i].join();
    }
    STOP_TIMER("precomputed randomness");
    AdjustPRFCounter(mac_factor * filterSpec.base_filters_size() * len);


    for (int i = 0; i < filterSpec.base_filters_size(); i++) {
        BaseFilter baseFilterSpec = filterSpec.base_filters(i);
        int len = mac_factor * (baseFilterSpec.is_point() ? DPFTables[baseFilterSpec.id()].first->windowSize : DCFTables[baseFilterSpec.id()].first->windowSize);

        if (*filter1 != NULL) {
            uint128_t *tmp0 = (uint128_t *)malloc(sizeof(uint128_t) * len);
            uint128_t *tmp1 = (uint128_t *)malloc(sizeof(uint128_t) * len);
            memcpy(tmp0, *filter0, sizeof(uint128_t) * len);
            memcpy(tmp1, *filter1, sizeof(uint128_t) * len);
            if (filterSpec.op_is_and()) {
                AndFilters(*filter0, *filter1, tmp0, tmp1, res0[i], res1[i], zero_shares[i], rand_coeff_shares0[i], rand_coeff_shares1[i], len, lin_comb_accumulator, lin_comb_mac_accumulator);
            } else {
                OrFilters(*filter0, *filter1, tmp0, tmp1, res0[i], res1[i], zero_shares[i], rand_coeff_shares0[i], rand_coeff_shares1[i], len, lin_comb_accumulator, lin_comb_mac_accumulator);
            }
            free(tmp0);
            free(tmp1);
            free(res0[i]);
            free(res1[i]);
        } else {
            *filter0 = res0[i];
            *filter1 = res1[i];
        }
    }
    if(malicious) {
        for (int i = 0; i < filterSpec.base_filters_size(); i++) {
            delete[] rand_coeff_shares0[i];
            delete[] rand_coeff_shares1[i];
        }
    }
}

void QueryServer::AggFilterQuery(string aggID, const CombinedFilter &filterSpec, uint128_t *res, uint128_t *mac, uint128_t *lc, uint128_t *lc_mac) {
    uint128_t *filter0;
    uint128_t *filter1;
    EvalFilter(&filter0, &filter1, filterSpec, lc, lc_mac);
    *res = 0;
    *mac = 0;
    int len = ValLists[aggID].first.size();
    for (int i = 0; i < len; i++) {
        // Get 3oo3 shares
        *res += ValLists[aggID].first[i] * filter0[i];
        *res += ValLists[aggID].second[i] * filter0[i];
        *res += ValLists[aggID].first[i] * filter1[i];
        if (malicious) {
            *mac += ValLists[aggID].first[i] * filter0[i + len];
            *mac += ValLists[aggID].second[i] * filter0[i + len];
            *mac += ValLists[aggID].first[i] * filter1[i + len];
        }
    }
    free(filter0);
    free(filter1);
}

CallData::CallData(QueryServer &server, Aggregate::AsyncService *service, ServerCompletionQueue *cq, RpcType type) :
        server(server), service(service), cq(cq), responderMult(&ctx), responderInit(&ctx), status(CREATE), type(type) {
    Proceed();
}

void CallData::Proceed() {
    if (status == CREATE) {
        status = PROCESS;
        if (type == MULT) {
            service->RequestSendMult(&ctx, &reqMult, &responderMult, cq, cq, this);
        } else if (type == INIT) {
            service->RequestSendSystemInit(&ctx, &reqInit, &responderInit, cq, cq, this);
        }
    } else if (status == PROCESS) {
        if (type == MULT) {
            new CallData(server, service, cq, MULT);
            server.FinishMultiply((const uint128_t *)reqMult.shares().c_str(), reqMult.shares().size());
            responderMult.Finish(respMult, Status::OK, this);
        } else if (type == INIT) {
            new CallData(server, service, cq, INIT);
            server.FinishSystemInit((const uint8_t *)reqInit.key().c_str());
            responderInit.Finish(respInit, Status::OK, this);
        }
        status = FINISH;
    } else {
        assert(status == FINISH);
        delete this;
    }
}

class QueryServiceImpl final : public Query::Service {
public:
    QueryServer &server;

    QueryServiceImpl(QueryServer &server) : server(server) {}

    Status SendDCFInit(ServerContext *context, const InitDCFRequest *req, InitDCFResponse *resp) override {
        server.DCFAddTable(req->id(), req->window_size(), req->num_buckets(), server.malicious);
        return Status::OK;
    }

    Status SendDPFInit(ServerContext *context, const InitDPFRequest *req, InitDPFResponse *resp) override {
        server.DPFAddTable(req->id(), req->window_size(), req->num_buckets(), server.malicious);
        return Status::OK;
    }

    Status SendATInit(ServerContext *context, const InitATRequest *req, InitATResponse *resp) override {
        server.AggTreeAddIndex(req->id(), req->depth(), (AggFunc)req->agg_func());
        return Status::OK;
    }

    Status SendListInit(ServerContext *context, const InitListRequest *req, InitListResponse *resp) override {
        server.AddValList(req->id(), req->window_size());
        return Status::OK;
    }

    Status SendDCFQuery(ServerContext *context, const QueryDCFRequest *req, QueryDCFResponse *resp) override {
        uint32_t len = 0;
        uint128_t *res0;
        uint128_t *res1;
        server.DCFQuery(&res0, &res1, req->id(), (const uint8_t *)req->key0().c_str(), (const uint8_t *)req->key1().c_str(), &len);
        for (int i = 0; i < len; i++) {
            res0[i] += res1[i];
        }
        resp->set_res(res0, sizeof(uint128_t) * len);
        free(res0);
        free(res1);
        return Status::OK;
    }

    Status SendATQuery(ServerContext *context, const QueryATRequest *req, QueryATResponse *resp) override {
        printf("Received AggTree query\n");
        int depth = server.AggTrees[req->id()].first->depth;
        uint128_t* res = (uint128_t*)malloc((depth+1)*sizeof(uint128_t));
        uint128_t* mac = (uint128_t*)malloc((depth+1)*sizeof(uint128_t));
        uint128_t* res_r = (uint128_t*)malloc((depth+1)*sizeof(uint128_t));
        uint128_t* mac_r = (uint128_t*)malloc((depth+1)*sizeof(uint128_t));
        server.AggTreeQuery(req->id(), (const uint8_t *)req->key0().c_str(), (const uint8_t *)req->key1().c_str(), res, mac, res_r, mac_r, &depth);
        resp->set_res((uint8_t *)res, (depth)*sizeof(uint128_t));
        resp->set_mac((uint8_t *)mac, (depth)*sizeof(uint128_t));
        resp->set_res_r((uint8_t *)res_r, (depth)*sizeof(uint128_t));
        resp->set_mac_r((uint8_t *)mac_r, (depth)*sizeof(uint128_t));
        printf("Finished processing AggTree query\n");
        return Status::OK;
    }

    Status SendAggQuery(ServerContext *context, const QueryAggRequest *req, QueryAggResponse *resp) {
        printf("Received aggregate query\n");
        uint128_t res, mac, lin_comb, lin_comb_mac;
        lin_comb = 0;
        lin_comb_mac = 0;
        server.AggFilterQuery(req->agg_id(), req->combined_filter(), &res, &mac, &lin_comb, &lin_comb_mac);
        resp->set_res((uint8_t *)&res, sizeof(uint128_t));
        resp->set_mac((uint8_t *)&mac, sizeof(uint128_t));
        resp->set_lin_comb((uint8_t *)&lin_comb, sizeof(uint128_t));
        resp->set_lin_comb_mac((uint8_t *)&lin_comb_mac, sizeof(uint128_t));
        printf("Finished processing aggregate query\n");
        return Status::OK;
    }

};

void handleAsyncRpcs(QueryServer &server, Aggregate::AsyncService &service, unique_ptr<ServerCompletionQueue> &cq) {
    new CallData(server, &service, cq.get(), INIT);
    new CallData(server, &service, cq.get(), MULT);
    void *tag;
    bool ok;
    while (true) {
        assert(cq->Next(&tag, &ok));
        assert(ok);
        static_cast<CallData*>(tag)->Proceed();
    }
}


void runServer(string publicAddrs[], string bindAddr, int serverID, int cores, bool malicious) {
    QueryServer s(publicAddrs, serverID, cores, malicious);
    QueryServiceImpl queryService(s);
    Aggregate::AsyncService asyncService;

    grpc::EnableDefaultHealthCheckService(true);
    grpc::reflection::InitProtoReflectionServerBuilderPlugin();

    ServerBuilder queryBuilder;
    queryBuilder.SetMaxReceiveMessageSize(-1);
    queryBuilder.AddListeningPort(bindAddr, grpc::InsecureServerCredentials());
    queryBuilder.RegisterService(&queryService);
    queryBuilder.RegisterService(&asyncService);
    unique_ptr<ServerCompletionQueue> cq(queryBuilder.AddCompletionQueue());
    unique_ptr<Server> queryServer(queryBuilder.BuildAndStart());

    s.service = &asyncService;
    s.cq = cq.get();
    thread t(handleAsyncRpcs, ref(s), ref(asyncService), ref(cq));
    s.StartSystemInit(publicAddrs);
    t.join();
}


__global__ void FSS_para1(int *a, int *b, int *c, int n) {
    int row = blockIdx.y * blockDim.y + threadIdx.y;
    int col = blockIdx.x * blockDim.x + threadIdx.x;

    if (row < n && col < n) {
        int sum = 0;
        for (int i = 0; i < n; ++i) {
            DCFServer::evalOneDCF(uint128_t row, block* k, a[row * n + i] * b[i * n + col];)
        }
        c[row * n + col] = sum;
    }
}

__global__ void FSS_para1(int *a, int *b, int *c, int n) {
    int row = blockIdx.y * blockDim.y + threadIdx.y;
    int col = blockIdx.x * blockDim.x + threadIdx.x;

    if (row < n && col < n) {
        int sum = 0;
        for (int i = 0; i < n; ++i) {
            DCFServer::evalOneDPF(uint128_t row, block* k, a[row * n + i] * b[i * n + col];)
        }
        c[row * n + col] = sum;
    }
}

int Process_Parall() {
    int *a, *b, *c;
    int *d_a, *d_b, *d_c;

    a = (int *)malloc(N * N * sizeof(int));
    b = (int *)malloc(N * N * sizeof(int));
    c = (int *)malloc(N * N * sizeof(int));

    for (int i = 0; i < N * N; ++i) {
        a[i] = rand() % 10;
        b[i] = rand() % 10;
    }

    cudaMalloc((void **)&d_a, N * N * sizeof(int));
    cudaMalloc((void **)&d_b, N * N * sizeof(int));
    cudaMalloc((void **)&d_c, N * N * sizeof(int));

    cudaMemcpy(d_a, a, N * N * sizeof(int), cudaMemcpyHostToDevice);
    cudaMemcpy(d_b, b, N * N * sizeof(int), cudaMemcpyHostToDevice);

    dim3 blockDim(16, 16);
    dim3 gridDim((N + blockDim.x - 1) / blockDim.x, (N + blockDim.y - 1) / blockDim.y);

    matrixMultiply<<<gridDim, blockDim>>>(d_a, d_b, d_c, N);

    cudaMemcpy(c, d_c, N * N * sizeof(int), cudaMemcpyDeviceToHost);

    std::cout << "Result matrix:" << std::endl;
    for (int i = 0; i < N; ++i) {
        for (int j = 0; j < N; ++j) {
            std::cout << c[i * N + j] << "\t";
        }
        std::cout << std::endl;
    }

    return 0;
}



int main(int argc, char *argv[]) {
    ifstream config_stream(argv[1]);
    json config;
    config_stream >> config;

    string addrs[NUM_SERVERS];
    for (int i = 0; i < NUM_SERVERS; i++) {
        addrs[i] = config[ADDRS][i];
    }
    string bindAddr = "0.0.0.0:" + string(config[PORT]);
    assert(argc == 2);
    int server_num = config[SERVER_NUM];
    assert(server_num == 0 || server_num == 1 || server_num == 2);
    runServer(addrs, bindAddr, server_num, config[CORES], config[MALICIOUS]);
}
