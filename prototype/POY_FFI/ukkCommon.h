/*
 * Copyright (c) David Powell <david@drp.id.au>
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation; either version 2 of the License, or (at your option) any later
 * version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program; if not, write to the Free Software Foundation, Inc., 59 Temple
 * Place - Suite 330, Boston, MA 02111-1307, USA.
 *
 */


// Name:         ukkCommon.h
// FileType:     C Header
// Created:      Tue May 11 13:23:45 1999
// Author:       David Powell
//
// Contains the common routines for ukk.alloc, ukk.noalign, ukk.checkp and ukk.dpa
// Has the mem allocation routines, in header files because they are all inline funcs
// Use the NO_ALLOC_ROUTINES flag to compile without alloc routines.
// Use the FIXED_NUM_PLANES flag to make routines allocate on d^2 memory.

#ifndef UKKCOMMON_H
#define UKKCOMMON_H

#include <limits.h>
#include <string.h>

#include "seq.h"
#include "ukkCheckp.h"

#define MAX_STR 100000

#define MAX_STATES 27                 // Maximum number of possible states, 3^3

#define MAX_COST (2 * MAX_STR)
#define INFINITY INT_MAX / 2

#define FULL_ALLOC_INFO 0

#define FIXED_NUM_PLANES 1

#define CellsPerBlock   10

typedef enum {match, del, ins} Trans;  // The 3 possible state-machine states

typedef struct {
    int elemSize;
    int abSize, acSize;
    int abOffset, acOffset;
    long abBlocks, acBlocks;

    #ifdef FIXED_NUM_PLANES
        int costSize;
    #endif

    long baseAlloc;
    void **basePtr;

    long memAllocated;
} AllocInfo;


#ifndef UKKCOMMON_C

    extern int mismatchCost;
    extern int gapOpenCost;
    extern int gapExtendCost;
    extern int deleteOpenCost;
    extern int deleteExtendCost;

    extern int neighbours[MAX_STATES];
    extern int contCost  [MAX_STATES];
    extern int secondCost[MAX_STATES];
    extern int transCost [MAX_STATES][MAX_STATES];
    extern int stateNum  [MAX_STATES];

    extern int numStates;
    extern int maxSingleStep;

    extern char aStr[MAX_STR];
    extern char bStr[MAX_STR];
    extern char cStr[MAX_STR];
    extern int  aLen, bLen, cLen;

#endif

#define maxSingleCost (maxSingleStep * 2)

int whichCharCost(char a, char b, char c);
int okIndex(int a, int da, int end);

// Setup routines
int  stateTransitionCost(int from, int to);
void step(int n, int *a, int *b, int *c);
int  neighbourNum(int i, int j, int k);
void transitions(int s, Trans st[3]);
char *state2str(int s) ;
int  countTrans(Trans st[3], Trans t);
void setup();

// Alignment checking routines
void checkAlign(char *al, int alLen, char *str, int strLen);
void revIntArray(int *arr, int start, int end);
void revCharArray(char *arr, int start, int end);
int  alignmentCost(int states[], char *al1, char *al2, char *al3, int len);

void *getPtr(AllocInfo *a, int ab, int ac, int d, int s);

int powell_3D_align (seq_p seqA,    seq_p seqB,    seq_p seqC,
                     seq_p retSeqA, seq_p retSeqB, seq_p retSeqC,
                     int mismatch, int gapOpen, int gapExtend);

// allocation routines. Were previously commented out.
void allocFinal(AllocInfo *a, void *flag, void *top);

#ifdef FIXED_NUM_PLANES
    AllocInfo allocInit(int elemSize, int costSize);
#else
    AllocInfo allocInit(int elemSize);
#endif


#endif // UKKCOMMON_H