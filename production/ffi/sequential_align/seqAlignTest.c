//
//  main.c
//  version_Haskell_bit
//
//  Created by Yu Xiang on 11/1/16.
//  Copyright © 2016 Yu Xiang. All rights reserved.
//


// recent changes: 1. Changed all malloc()s to calloc()s. calloc() initializes memory, as well as allocating.
//                    This could very easily be changed back for speed efficiency, but it kept showing up as an error in valgrind.
//                 2. Added a return value of 2. Now 0 is success, 1 is memory allocation error, 2 is inputs were both 0 length.
//                 3. Changed strncpy(retAlign, _, _) to be a series of loops, each terminating at '*'.
//                    Also terminated both strings with '\0', for good measure.
//                 4. Made INIT_LENGTH a const.
//                 5. INIT_LENGTH = 2 * retAlign->alignmentLength - 1.
//                 6. Made LENGTH a const.
//                 7. Some style changes to enhance legibility for myself.

#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

#include "costMatrixWrapper.h"
#include "dynamicCharacterOperations.h"
//#include "seqAlignForHaskell.h"
#include "seqAlignInterface.h"

#define __STDC_FORMAT_MACROS

int main() {

    const size_t TCM_LENGTH    = 25;
    const size_t ALPHABET_SIZE = 5;

    int tcm[25] = {0,1,1,1,2, 1,0,1,1,2, 1,1,0,1,2, 1,1,1,0,2, 2,2,2,2,0};

    if ( TCM_LENGTH != ALPHABET_SIZE * ALPHABET_SIZE ) {
        printf("tcm wrong size\n");
        exit(1);
    }

    uint64_t s1[14] = {1, 2, 4, 8, 2, 3, 5, 1, 12, 4, 4, 8, 14, 1};
    uint64_t s2[12]  = {4, 2, 1, 8, 4, 9, 4, 1,  8, 4, 4, 8};

    costMatrix_p costMatrix = matrixInit(ALPHABET_SIZE, tcm);

    dynChar_t *seqA  = malloc(sizeof(dynChar_t));
    seqA->alphSize   = ALPHABET_SIZE;
    seqA->numElems   = 14;
    seqA->dynCharLen = 1;
    seqA->dynChar    = intArrToBitArr(ALPHABET_SIZE, seqA->numElems, s1);


    dynChar_t *seqB  = malloc(sizeof(dynChar_t));
    seqB->alphSize   = ALPHABET_SIZE;
    seqB->numElems   = 12;
    seqB->dynCharLen = 1;
    seqB->dynChar    = intArrToBitArr(ALPHABET_SIZE, seqB->numElems, s2);

    int success = 1;


    alignResult_t *result = malloc(sizeof(alignResult_t));

    success = performSequentialAlignment(seqA, seqB, costMatrix, result);

    printf("%zu\n", result->finalLength);

    if (success == 0) {
        printf("\nSuccess!\n\n");
	/*	
        printf("The aligned sequences are:\n");
        printf("  sequence 1:      [");
        for(size_t i = 0; i < result->finalLength; ++i) {
            printf("%llu, ", result->finalChar1[i]);
        }
        printf("]\n  sequence 2:      [");
        for(size_t i = 0; i < result->finalLength; ++i) {
            printf("%llu, ", result->finalChar2[i]);
        }
        printf("]\n");
        printf("]\n  median sequence:  [");
        for(size_t i = 0; i < result->finalLength; ++i) {
            printf("%llu, ", result->medianChar[i]);
        }
        printf("]\n");
        */
        printf("The cost of the alignment is: %zu\n", result->finalWt);

    } else {
        printf("Fail!\n");
    }
    // free(retAlign->seq1);
    // free(retAlign->seq2);
    matrixDestroy(costMatrix);

}


/**
 *  A sample program that takes in two dynamic characters and returns two aligned dynamic chars,
 *  in the form of an alignResult_t. The third character is allocated on Haskell side and passed in by reference.
 *  Returns 0 on correct exit, 1 on allocation failure. This was used to test the Haskell FFI.
 */
/*
int exampleInterfaceFn(dynChar_t* seqA, dynChar_t* seqB, alignResult_t* result) {

    uint64_t* seqA_main = dynCharToIntArr(seqA);
    uint64_t* seqB_main = dynCharToIntArr(seqB);

    retType_t* retAlign = malloc( sizeof(retType_t) );

    long int length = seqA->numElems + seqB->numElems + 5;
    retAlign->seq1 = calloc(length, sizeof(int));
    retAlign->seq2 = calloc(length, sizeof(int));
    if( retAlign->seq1 == NULL || retAlign->seq2 == NULL ) {
        printf("Memory failure!\n");
        return 1;
    }
    retAlign->alignmentLength = length;

    // Call aligner with TCM here: int success = aligner(seqA_main, seqB_main, costMtx_t* tcm, &retAlign);
    // The following as an example
    const size_t TCM_LENGTH = 25;
    int tcm[25] = {0,1,1,1,2, 1,0,1,1,2, 1,1,0,1,2, 1,1,1,0,2, 2,2,2,2,0};
    size_t ALPHABET_SIZE = 5;
    if ( TCM_LENGTH != ALPHABET_SIZE * ALPHABET_SIZE ) {
        printf("tcm wrong size\n");
        exit(1);
    }

    costMatrix_p costMatrix = matrixInit(ALPHABET_SIZE, tcm);

    int success = aligner(seqA_main, seqA->numElems, seqB_main, seqB->numElems, seqA->alphSize, costMatrix, retAlign);
    result->finalChar1 = intArrToBitArr (seqA->alphSize, retAlign->alignmentLength, retAlign->seq1);
    result->finalChar2 = intArrToBitArr (seqA->alphSize, retAlign->alignmentLength, retAlign->seq2);

    result->finalWt      = retAlign->weight;
    result->finalLength  = retAlign->alignmentLength;

    freeRetType(retAlign);
    free(retAlign);

    return success;
}
*/
