#include <limits.h>
#include <stdio.h>
#include <stdlib.h>

#include "seqAlign.h"
#include "debug_constants.h"
#include "costMatrix.h"
#include "nwMatrices.h"
#include "ukkCheckp.h"
#include "ukkCommon.h"



void initializeNWMtx(size_t cap_seq1, size_t cap_seq2, size_t cap_seq3, int costMtxLcm, nw_matrices_p retMtx);

void initializeSeq(seq_p retSeq, size_t allocSize);

void resetSeqValues(seq_p retSeq);

/** Find distance between an unambiguous nucleotide and an ambiguous ambElem. Return that value and the median.
 *  @param ambElem is ambiguous input.
 *  @param nucleotide is unambiguous.
 *  @param median is used to return the calculated median value.
 *
 *  This fn is necessary because there isn't yet a cost matrix set up, so it's not possible to
 *  look up ambElems, therefore we must loop over possible values of the ambElem
 *  and find the lowest cost median.
 *
 *  Requires symmetric, if not metric, matrix.
 */
int distance (int const *tcm, int alphSize, int nucleotide, int ambElem);

// may return cost_matrices_2d or cost_matrices_3d, so void *
// no longer setting max, as algorithm to do so is unclear: see note in .c file
void setup2dCostMtx(int* tcm, size_t alphSize, int gap_open, cost_matrices_2d_p retMtx);

void setup3dCostMtx(int* tcm, size_t alphSize, int gap_open, cost_matrices_3d_p retMtx);

void freeCostMtx(void * input, int is_2d);

void freeNWMtx(nw_matrices_p input);

void freeSeq(seq_p toFree);
