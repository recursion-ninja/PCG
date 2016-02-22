//
//  Header.h
//  haskellcode_version
//
//  Created by Yu Xiang on 2/17/16.
//  Copyright © 2016 Yu Xiang. All rights reserved.
//

#ifndef yuAlign_h
#define yuAlign_h

struct align {
    int partialWt;
    int partialTrueWt;
    char* partialAlign; // EDIT: made it dynamically allocable.
    int posStringA;   // position at stringA
    int posStringB;   // position at stringB
    int posTrueA;     // position without gap
    int posTrueB;     // position without gap
    int flagWhichTree;  // belongs to first or second tree
};

// EDIT: Added this struct so the job on my end would be easier.
// Wasn't sure what the final weight was, so copied partialTrueWt.

struct retType {
    int weight;
    char* alignment;
};

int trueWt(struct align *path, int a, int b);

// EDIT: rectified with .c file.
int f(/*char *seq1, char *seq2, int wtInsertDel, int wtSub, struct retType* retAlign*/);


#endif /* Header_h */
