/* POY 4.0 Beta. A phylogenetic analysis program using Dynamic Homologies.    */
/* Copyright (C) 2007  Andrés Varón, Le Sy Vinh, Illya Bomash, Ward Wheeler,  */
/* and the American Museum of Natural History.                                */
/*                                                                            */
/* This program is free software; you can redistribute it and/or modify       */
/* it under the terms of the GNU General Public License as published by       */
/* the Free Software Foundation; either version 2 of the License, or          */
/* (at your option) any later version.                                        */
/*                                                                            */
/* This program is distributed in the hope that it will be useful,            */
/* but WITHOUT ANY WARRANTY; without even the implied warranty of             */
/* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the              */
/* GNU General Public License for more details.                               */
/*                                                                            */
/* You should have received a copy of the GNU General Public License          */
/* along with this program; if not, write to the Free Software                */
/* Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301   */
/* USA                                                                        */

/******************************************************************************/
/*                        Pairwise Standard Alignment                         */
/******************************************************************************/
/*
 * As standard, all the caml binding functions are called algn_CAML_<function
 * name>
 */

/** Fill a row in a two dimentional alignment
 *
 *  When pairwise alignment is performed, two sequences are compared over a
 *  transformation cost matrix. Let's call them sequences x and y, written over
 *  some alphabet a of length |a|. Each base of x
 *  is represented by a column in the transformation cost matrix and each base of
 *  y by a row. However, note that the actual values that are added during the
 *  alignment are produced by comparing every single base of x with only |a|
 *  elements. Now, in order to make these operations vectorizable, we perform
 *  the comparisons with |a| precalculated vectors. This puts in context the
 *  explanation of each parameter in the function.
 *
 *  @param curRow is the cost matrix row to be filled with values.
 *  @param prevRow is the row above curRow in the cost matrix being filled.
 *  @param gap_row is the cost of aligning each base in x with a gap.
 *  @param alg_row is the cost of aligning each base in x with the base
 *      represented by the base of the row of curRow in y.
 *  @param dirMtx is the directional matrix for the backtrace
 *  @param c is the cost of an insertion. An insertion can only occur for one
 *      particular base in the alphabet, corresponding to the base in y represented
 *      by the row that is being filled.
 *  @param st is the starting cell to be filled.
 *  @param end is the final cell to be filled.
 *
 *  If you modify this code check algn_fill_cube as there is similar code there
 *  used in the first plane of the alignment. I didn't use this function because
 *  the direction codes are different for three dimensional alignments.
 */

#include <assert.h>
#include <limits.h>
#include <locale.h>
#include <stdio.h>
#include <stdlib.h>
#include <wchar.h>


// #include "array_pool.h" ARRAY_POOL_DELETE
#include "algn.h"
#include "debug.h"
// #include "cm.h"
// #include "matrices.h"
// #include "seq.h"
// #include "zarr.h"

/*
#include "matrices.c"
#include "cm.c"
#include "seq.c"
#include "array_pool.c"
*/

#ifdef DEBUG_ALL_ASSERTIONS
int *_algn_max_matrix = NULL;
DIRECTION_MATRIX *_algn_max_direction = NULL;
#endif

#if ( __GNUC__ && __MMX__ )
static inline void
algn_fill_row (int *curRow, const int *prevRow, const int *gap_row, 
               const int *alg_row, DIRECTION_MATRIX *dirMtx, int c, int i, int end) {


    register int aa, bb, cc;
    register const int TWO = 0x200;
    register const int ZERO = 0;

    bb = curRow[i - 1];

    for (; i <= end - 7; i+=8) {


        aa = prevRow[i - 1] + alg_row[i]; // aka tmp3
        bb += gap_row[i]; // aka tmp2
        cc = prevRow[i] + c; // aka tmp1
        /**
         *  The algorithm has not changed. Only the conditional branches been eliminated for
         *  better performance.
         *
         *  Since gcc (4.0.3 at least) didn't generate cmov's, we changed the code manually.
         *  Things that have been done to optimize this function:
         *      - assembly code for determining min(aa, bb, cc) and getting the bit pattern
         *        loop unrolling with a factor of 8, to still keep this function inlined
         *      - rearrangement of expressions => better register usage and (probably)
         *        fewer cache misses

         *  Restrictions:
         *  ALIGN is bound to the value 4, INSERT to 2 and DELETE to 1
         *  If these constants change, there will be problems with the assembler code, 
         *  since it is really optimized for this purpose

         *  Furthermore, this code only works with the gnu compiler (but shouldn't be
         *  hard to switch to icc), so add
         *  #ifdef __GNUC__ as a macro for this section. I also suppose that cmov's
         *  can be handled by most of the computers used today
         *  (of those using this program at least).

         *  I have also removed the debug sections. These can of course be added if
         *  a debug is needed.
         *  I recommend that debugging is only used with the original function, 
         *  since this one generates exactly same results.
         */


        __asm__(
            "cmp %0, %1\n\t"    // compare aa with bb (the needed cmp flag remains even if registers are switched)
            "cmovg %0, %1\n\t"  // if bb > aa was flagged, put aa into bb's register. Now we know that bb is always the smallest value
            "mov $0x0, %0\n\t"  // aa is now trash and will not be used anymore. Clean the register (set it to 0x0)
            "cmovle %4, %0\n\t" // if bb <= aa was flagged in the first instruction, then put TWO (0x200) into register 0 (aa)
            "setge %b0\n\t"     // if bb >= aa was flagged in the first instruction, then set the lowest byte in register 0 to 1 (0x01)
            "cmp %1, %2\n\t"    // compare reg.1 (the lowest of aa and bb) with cc.
            "cmovl %2, %1\n\t"  // if cc < bb was flagged in the 2nd comparison, then move cc into bb. min(aa, bb, cc) is now stored in bb.
            "mov $0x4, %2\n\t"  // put a 4 (ALIGN) in register 2 (cc) since cc is trash.
            "cmovl %3, %0\n\t"  // if cc < bb was flagged in the 2nd comparison, then clear register 0.
            "cmovg %3, %2\n\t"  // if cc > bb was flagged, then clean the register. (Note that you can only move register->register with a cmov.)
            "add %b0, %h0\n\t"  // finally, add low byte and high byte of register 0 into register 0's low byte.
            "add %h0, %b2\n\t"  // add high byte from reg.0 to low byte in reg.2 (cc) and we are done. cc contains now the bitpattern.
            : "+Q" (aa), "+r" (bb), "+Q" (cc)   // registers: aa = %0, bb = %1, cc = %2
            : "r" (ZERO), "r" (TWO)         // ZERO = %3, TWO = %4
        );

        curRow[i] = bb; // bb is min(aa, bb, cc)
        dirMtx[i] = cc; // cc is the bitpattern


        aa = prevRow[i] + alg_row[i + 1];
        bb += gap_row[i + 1]; // bb is already assigned the minimum value of the three to be compared, so loading bb from memory would be waste.
        cc = prevRow[i + 1] + c;


        __asm__(
            "cmp %0, %1\n\t"
            "cmovg %0, %1\n\t"
            "mov $0x0, %0\n\t"
            "cmovle %4, %0\n\t"
            "setge %b0\n\t"
            "cmp %1, %2\n\t"
            "cmovl %2, %1\n\t"
            "mov $0x4, %2\n\t"
            "cmovl %3, %0\n\t"
            "cmovg %3, %2\n\t"
            "add %b0, %h0\n\t"
            "add %h0, %b2\n\t"
            : "+Q" (aa), "+r" (bb), "+Q" (cc)
            : "r" (ZERO), "r" (TWO)
        );

        curRow[i + 1] = bb;
        dirMtx[i + 1] = cc;

        aa = prevRow[i + 1] + alg_row[i + 2];
        bb += gap_row[i + 2];
        cc = prevRow[i + 2] + c;


        __asm__(
            "cmp %0, %1\n\t"
            "cmovg %0, %1\n\t"
            "mov $0x0, %0\n\t"
            "cmovle %4, %0\n\t"
            "setge %b0\n\t"
            "cmp %1, %2\n\t"
            "cmovl %2, %1\n\t"
            "mov $0x4, %2\n\t"
            "cmovl %3, %0\n\t"
            "cmovg %3, %2\n\t"
            "add %b0, %h0\n\t"
            "add %h0, %b2\n\t"
            : "+Q" (aa), "+r" (bb), "+Q" (cc)
            : "r" (ZERO), "r" (TWO)
        );

        curRow[i + 2] = bb;
        dirMtx[i + 2] = cc;

        aa = prevRow[i + 2] + alg_row[i + 3];
        bb += gap_row[i + 3];
        cc = prevRow[i + 3] + c;


        __asm__(
            "cmp %0, %1\n\t"
            "cmovg %0, %1\n\t"
            "mov $0x0, %0\n\t"
            "cmovle %4, %0\n\t"
            "setge %b0\n\t"
            "cmp %1, %2\n\t"
            "cmovl %2, %1\n\t"
            "mov $0x4, %2\n\t"
            "cmovl %3, %0\n\t"
            "cmovg %3, %2\n\t"
            "add %b0, %h0\n\t"
            "add %h0, %b2\n\t"
            : "+Q" (aa), "+r" (bb), "+Q" (cc)
            : "r" (ZERO), "r" (TWO)
        );

        curRow[i + 3] = bb;
        dirMtx[i + 3] = cc;



        aa = prevRow[i + 3] + alg_row[i + 4];
        bb += gap_row[i + 4];
        cc = prevRow[i + 4] + c;


        __asm__(
            "cmp %0, %1\n\t"
            "cmovg %0, %1\n\t"
            "mov $0x0, %0\n\t"
            "cmovle %4, %0\n\t"
            "setge %b0\n\t"
            "cmp %1, %2\n\t"
            "cmovl %2, %1\n\t"
            "mov $0x4, %2\n\t"
            "cmovl %3, %0\n\t"
            "cmovg %3, %2\n\t"
            "add %b0, %h0\n\t"
            "add %h0, %b2\n\t"
            : "+Q" (aa), "+r" (bb), "+Q" (cc)
            : "r" (ZERO), "r" (TWO)
        );

        curRow[i + 4] = bb;
        dirMtx[i + 4] = cc;


        aa = prevRow[i + 4] + alg_row[i + 5];
        bb += gap_row[i + 5];
        cc = prevRow[i + 5] + c;


        __asm__(
            "cmp %0, %1\n\t"
            "cmovg %0, %1\n\t"
            "mov $0x0, %0\n\t"
            "cmovle %4, %0\n\t"
            "setge %b0\n\t"
            "cmp %1, %2\n\t"
            "cmovl %2, %1\n\t"
            "mov $0x4, %2\n\t"
            "cmovl %3, %0\n\t"
            "cmovg %3, %2\n\t"
            "add %b0, %h0\n\t"
            "add %h0, %b2\n\t"
            : "+Q" (aa), "+r" (bb), "+Q" (cc)
            : "r" (ZERO), "r" (TWO)
        );

        curRow[i + 5] = bb;
        dirMtx[i + 5] = cc;

        aa = prevRow[i + 5] + alg_row[i + 6];
        bb += gap_row[i + 6];
        cc = prevRow[i + 6] + c;


        __asm__(
            "cmp %0, %1\n\t"
            "cmovg %0, %1\n\t"
            "mov $0x0, %0\n\t"
            "cmovle %4, %0\n\t"
            "setge %b0\n\t"
            "cmp %1, %2\n\t"
            "cmovl %2, %1\n\t"
            "mov $0x4, %2\n\t"
            "cmovl %3, %0\n\t"
            "cmovg %3, %2\n\t"
            "add %b0, %h0\n\t"
            "add %h0, %b2\n\t"
            : "+Q" (aa), "+r" (bb), "+Q" (cc)
            : "r" (ZERO), "r" (TWO)
        );

        curRow[i + 6] = bb;
        dirMtx[i + 6] = cc;

        aa = prevRow[i + 6] + alg_row[i + 7];
        bb += gap_row[i + 7];
        cc = prevRow[i + 7] + c;


        __asm__(
            "cmp %0, %1\n\t"
            "cmovg %0, %1\n\t"
            "mov $0x0, %0\n\t"
            "cmovle %4, %0\n\t"
            "setge %b0\n\t"
            "cmp %1, %2\n\t"
            "cmovl %2, %1\n\t"
            "mov $0x4, %2\n\t"
            "cmovl %3, %0\n\t"
            "cmovg %3, %2\n\t"
            "add %b0, %h0\n\t"
            "add %h0, %b2\n\t"
            : "+Q" (aa), "+r" (bb), "+Q" (cc)
            : "r" (ZERO), "r" (TWO)
        );

        curRow[i + 7] = bb;
        dirMtx[i + 7] = cc;


    }



    for (; i <= end; i++) {

        aa = prevRow[i - 1] + alg_row[i];
        bb += gap_row[i];
        cc = prevRow[i] + c;


        __asm__(
            "cmp %0, %1\n\t"
            "cmovg %0, %1\n\t"
            "mov $0x0, %0\n\t"
            "cmovle %4, %0\n\t"
            "setge %b0\n\t"
            "cmp %1, %2\n\t"
            "cmovl %2, %1\n\t"
            "mov $0x4, %2\n\t"
            "cmovl %3, %0\n\t"
            "cmovg %3, %2\n\t"
            "add %b0, %h0\n\t"
            "add %h0, %b2\n\t"
            : "+Q" (aa), "+r" (bb), "+Q" (cc)
            : "r" (ZERO), "r" (TWO)
        );

        curRow[i] = bb;
        dirMtx[i] = cc;


    }
    return;

}
#else /* __GNUC__ */

static inline void
algn_fill_row (int *curRow, const int *prevRow, const int *gap_row, 
               const int *alg_row, DIRECTION_MATRIX *dirMtx, int c, int st, int end) {
    int i, tmp1, tmp2, tmp3;

    for (i = st; i <= end; i++) {
        /* try align with substitution */
        tmp1 = prevRow[i] + c;
        tmp2 = curRow[i - 1] + gap_row[i];
        tmp3 = prevRow[i - 1] + alg_row[i];
        /* check whether insertion is better */
        /* This option will allow all the possible optimal paths to be stored
         * concurrently on the same backtrace matrix. This is important for the
         * sequences being able to choose the appropriate direction while
         * keeping the algorithm that assumes that seq2 is at most as long as seq1.
         * */
        if (tmp1 < tmp3) {
            if (tmp1 < tmp2) {
                curRow[i] = tmp1;
                dirMtx[i] = DELETE;
            }
            else if (tmp2 < tmp1) {
                curRow[i] = tmp2;
                dirMtx[i] = INSERT;
            }
            else {
                curRow[i] = tmp2;
                dirMtx[i] = (INSERT | DELETE);
            }
        }
        else if (tmp3 < tmp1) {
            if (tmp3 < tmp2) {
                curRow[i] = tmp3;
                dirMtx[i] = ALIGN;
            }
            else if (tmp2 < tmp3) {
                curRow[i] = tmp2;
                dirMtx[i] = INSERT;
            }
            else {
                curRow[i] = tmp2;
                dirMtx[i] = (ALIGN | INSERT);
            }
        }
        else { /* tmp3 == tmp1 */
            if (tmp3 < tmp2) {
                curRow[i] = tmp3;
                dirMtx[i] = (ALIGN | DELETE);
            }
            else if (tmp2 < tmp3) {
                curRow[i] = tmp2;
                dirMtx[i] = INSERT;
            }
            else {
                curRow[i] = tmp2;
                dirMtx[i] = (DELETE | INSERT | ALIGN);
            }
        }
        if (DEBUG_DIR_M) {
            /* Print the alignment matrix */
            if (INSERT & dirMtx[i])
                printf ("I");
            if (DELETE & dirMtx[i])
                printf ("D");
            if (ALIGN & dirMtx[i])
                printf ("A");
            printf ("\t");
        }
        if (DEBUG_COST_M) {
            /* Print the cost matrix */
            printf ("%d\t", curRow[i]);
            fflush (stdout);
        }
    }
    if (DEBUG_COST_M || DEBUG_DIR_M)  {
        printf ("\n");
        fflush (stdout);
    }
    return;
}
#endif /* __GNUC__ */

static inline void
algn_fill_ukk_right_cell (int *curRow, const int *prevRow, const int *gap_row, 
                          const int *alg_row, DIRECTION_MATRIX *dirMtx, int c, int pos) {
    int tmp2, tmp3;
    /* try align with substitution */
    tmp2 = curRow[pos - 1] + gap_row[pos];
    tmp3 = prevRow[pos - 1] + alg_row[pos];
    /* check whether insertion is better */
    if (tmp2 < tmp3) {
        curRow[pos] = tmp2;
        dirMtx[pos] = INSERT;
    }
    else if (tmp3 < tmp2) {
        curRow[pos] = tmp3;
        dirMtx[pos] = ALIGN;
    }
    else {
        curRow[pos] = tmp3;
        dirMtx[pos] = INSERT | ALIGN;
    }
    if (DEBUG_DIR_M) {
        /* Print the alignment matrix */
        if (INSERT & dirMtx[pos])
            printf ("I");
        if (DELETE & dirMtx[pos])
            printf ("D");
        if (ALIGN & dirMtx[pos])
            printf ("A");
        printf ("\t");
    }
    if (DEBUG_COST_M) {
        /* Print the cost matrix */
        printf ("%d\t", curRow[pos]);
        fflush (stdout);
    }
    if (DEBUG_COST_M || DEBUG_DIR_M) {
        printf ("\n");
        fflush (stdout);
    }
    return;
}

static inline void
algn_fill_ukk_left_cell (int *curRow, const int *prevRow, const int *gap_row, 
                         const int *alg_row, DIRECTION_MATRIX *dirMtx, int c, int pos) {
    int tmp1, tmp3;
    /* try align with substitution */
    tmp1 = prevRow[pos] + c;
    tmp3 = prevRow[pos - 1] + alg_row[pos];
        if (tmp1 < tmp3) {
            curRow[pos] = tmp1;
            dirMtx[pos] = DELETE;
        }
        else if (tmp3 < tmp1) {
            curRow[pos] = tmp3;
            dirMtx[pos] = ALIGN;
        }
        else {
            curRow[pos] = tmp1;
            dirMtx[pos] = ALIGN | DELETE;
        }
    if (DEBUG_DIR_M) {
        /* Print the alignment matrix */
        if (INSERT & dirMtx[pos])
            printf ("I");
        if (DELETE & dirMtx[pos])
            printf ("D");
        if (ALIGN & dirMtx[pos])
            printf ("A");
        printf ("\t");
    }
    if (DEBUG_COST_M) {
        /* Print the cost matrix */
        printf ("%d\t", curRow[pos]);
        fflush (stdout);
    }
    return;
}

static inline void
algn_fill_last_column (int *curRow, const int *prevRow, int tlc, int l, DIRECTION_MATRIX *dirMtx) {
    int cst;
    if (l > 0) {
        cst = tlc + prevRow[l];
        if (cst < curRow[l]) {
            curRow[l] = cst;
            dirMtx[l] = DELETE;
        }
        else if (cst == curRow[l])
            dirMtx[l] = dirMtx[l] | DELETE;
    }
    return;
}

static inline void
algn_fill_full_row (int *curRow, const int *prevRow, const int *gap_row, 
                    const int *alg_row, DIRECTION_MATRIX *dirMtx, int c, int tlc, int l) {
    /* first entry is delete */
    curRow[0] = c + prevRow[0];
    dirMtx[0] = DELETE;
    if (DEBUG_COST_M) {
        printf ("%d\t", curRow[0]);
        fflush (stdout);
    }
    if (DEBUG_DIR_M) {
        printf ("D\t");
    }
    algn_fill_row (curRow, prevRow, gap_row, alg_row, dirMtx, c, 1, l - 1);
    algn_fill_last_column (curRow, prevRow, tlc, l - 1, dirMtx);
    return;
}

void
algn_fill_first_row (int *curRow, DIRECTION_MATRIX *dirMtx, int len, int const *gap_row) {
    int i;
    /* We fill the first cell to start with */
    curRow[0] = 0;
    dirMtx[0] = ALIGN;
    /* Now the rest of the row */
    if (DEBUG_DIR_M)
        printf ("A\t");
    if (DEBUG_DIR_M) {
        printf ("%d\t", curRow[0]);
        fflush (stdout);
    }
    for (i = 1; i < len; i++) {
        curRow[i] = curRow[i - 1] + gap_row[i];
        dirMtx[i] = INSERT;
        if (DEBUG_DIR_M)
            printf ("I\t");
        if (DEBUG_DIR_M) {
            printf ("%d\t", curRow[i]);
            fflush (stdout);
        }
    }
    return;
}

void
algn_fill_first_cell (int *curRow, int prevRow, DIRECTION_MATRIX *dirMtx, int gap) {
    *curRow = prevRow + gap;
    *dirMtx = DELETE;
    if (DEBUG_DIR_M)
        printf ("D\t");
    if (DEBUG_DIR_M) {
        printf ("%d\t", *curRow);
        fflush (stdout);
    }
    return;
}

/* In the following three functions, we maintain the following invariants in
 * each loop:
 * 1. curRow is a row that has not been filled and is the next to be.
 * 4. dirMtx is the current row of the direction matrix
 * 2. prevRow is the previous row, located right above curRow, which has been filled
 *    already.
 * 3. i is the number of the row of curRow in its containing matrix
 * 5. gap_row is the cost of aligning each base of seq2 with a gap. This is
 *    constant for all the loop.
 * 6. cur_seq1 is the i'th base of seq1
 * 7. const_val is the cost of cur_seq1 aligned with a gap
 * 8. alg_row is the vector of costs of aligning seq2 with cur_seq1
 */

int *
algn_fill_extending_right (const seq_p seq1, int *precalcMtx, int seq1_len, int seq2_len,  
                           int *curRow, int *prevRow, DIRECTION_MATRIX *dirMtx, const cost_matrices_2d_p c, 
                           int start_row, int end_row, int len) {
    int i;
    int *tmp, cur_seq1, const_val;
    const int *gap_row, *alg_row;
    /** Invariants block
     * len is the number of items in the row to be filled **/
    i = start_row;
    /* This is what we will perform conceptually, I will stop using the
     * cm_get_precal_row function to speed this up a little bit
    gap_row = cm_get_precal_row (precalcMtx, cm_get_gap (c), seq2_len);
    */
    gap_row = precalcMtx + (c->gap * seq2_len);
    while (i < end_row) {
        /** Invariants block */
        cur_seq1 = seq1->begin[i];
        const_val = cm_calc_cost (c->cost, cur_seq1, c->gap, c->lcm);
        /* This is conceptually what we do in the next line
        alg_row = cm_get_precal_row (precalcMtx, cur_seq1, seq2_len);
        */
        alg_row = precalcMtx + (cur_seq1 * seq2_len);
        /* Align! */
        algn_fill_first_cell (curRow, prevRow[0], dirMtx, alg_row[0]);
        algn_fill_row (curRow, prevRow, gap_row, alg_row, dirMtx, const_val, 1, len - 2);
        algn_fill_ukk_right_cell (curRow, prevRow, gap_row, alg_row, dirMtx, const_val, len - 1);
        /** Invariants block */
        tmp = curRow;
        curRow = prevRow;
        prevRow = tmp;
        i++;
        dirMtx += seq2_len;
        len++;
    }
    return (curRow);
}

int *
algn_fill_extending_left_right (const seq_p seq1, int *precalcMtx, int seq1_len, 
                                int seq2_len,  int *curRow, int *prevRow, DIRECTION_MATRIX *dirMtx, 
                                const cost_matrices_2d_p c, int start_row, 
                                int end_row, int start_column, int len) {
    int i;
    int *tmp, cur_seq1, const_val;
    const int *gap_row, *alg_row;
    /** Invariants block
     * len is the number of cells to fill in the current row minus 1
     * start_column is the first cell to fill in the row */
    i = start_row;
    /* Conceptually,
       gap_row = cm_get_precal_row (precalcMtx, cm_get_gap (c), seq2_len);
    */
    gap_row = precalcMtx + (c->gap * seq2_len);
    len--;
    while (i < end_row) {
        /** Invariants block */
        cur_seq1 = seq1->begin[i];
        const_val = cm_calc_cost (c->cost, cur_seq1, c->gap, c->lcm);
        /* Conceptually,
           alg_row = cm_get_precal_row (precalcMtx, cur_seq1, seq2_len);
        */
        alg_row = precalcMtx + (cur_seq1 * seq2_len);
        /* Align! */
        algn_fill_ukk_left_cell (curRow, prevRow, gap_row, alg_row, dirMtx, const_val, start_column);
        algn_fill_row (curRow, prevRow, gap_row, alg_row, dirMtx, const_val, 
                       start_column + 1, start_column + (len - 2));
        algn_fill_ukk_right_cell (curRow, prevRow, gap_row, alg_row, dirMtx, const_val, 
                                  start_column + len - 1);
        /** Invariants block */
        tmp = curRow;
        curRow = prevRow;
        prevRow = tmp;
        i++;
        dirMtx += seq2_len;
        start_column++;
    }
    return (curRow);
}

int *
algn_fill_extending_left (const seq_p seq1, int *precalcMtx, int seq1_len, 
                          int seq2_len,  int *curRow, int *prevRow, DIRECTION_MATRIX *dirMtx, 
                          const cost_matrices_2d_p c, int start_row, 
                          int end_row, int start_column, int len) {
    int i;
    int *tmp, cur_seq1, const_val, const_val_tail;
    const int *gap_row, *alg_row;
    /** Invariants block
     *  start_column is the first cell to fill in the row
     *  len is the number of cells to fill in the current row minus 1 */
    i = start_row;
    /* Conceptually,
       gap_row = cm_get_precal_row (precalcMtx, cm_get_gap (c), seq2_len);
    */
    gap_row = precalcMtx + (c->gap * seq2_len);
    while (i < end_row) {
        /** Invariants block */
        cur_seq1 = seq1->begin[i];
        const_val = cm_calc_cost (c->cost, cur_seq1, c->gap, c->lcm);
        const_val_tail = (cm_get_tail_cost (c))[cur_seq1];
        /* Conceptually,
           alg_row = cm_get_precal_row (precalcMtx, cur_seq1, seq2_len);
        */
        alg_row = precalcMtx + (cur_seq1 * seq2_len);
        /* Align! */
        algn_fill_ukk_left_cell (curRow, prevRow, gap_row, alg_row, dirMtx, const_val, start_column);
        algn_fill_row (curRow, prevRow, gap_row, alg_row, dirMtx, const_val, 
                       start_column + 1, start_column + len - 1);
        algn_fill_last_column (curRow, prevRow, const_val_tail, start_column + len - 1, dirMtx);
        /** Invariants block */
        tmp = curRow;
        curRow = prevRow;
        prevRow = tmp;
        i++;
        dirMtx += seq2_len;
        start_column++;
        len--;
    }
    if (DEBUG_COST_M) {
        printf ("ALIGNALL gap cost\n");
        fflush (stdout);
        for (i = 0; i < seq2_len; i++) {
            printf ("%d\t", gap_row[i]);
            fflush (stdout);
        }
        printf ("\n");
        printf ("The ALIGN23 - gap cost is %d\n", const_val);
        fflush (stdout);
    }

    return (curRow);
}

int *
algn_fill_no_extending (const seq_p seq1, int *precalcMtx, int seq1_len, 
                        int seq2_len,  int *curRow, int *prevRow, DIRECTION_MATRIX *dirMtx, 
                        const cost_matrices_2d_p c, int start_row, 
                        int end_row) {
    int i;
    int *tmp, cur_seq1, const_val, const_val_tail;
    const int *gap_row, *alg_row;
    /** Invariants block */
    i = start_row;
    /* Conceptually,
       gap_row = cm_get_precal_row (precalcMtx, cm_get_gap (c), seq2_len);
    */
    gap_row = precalcMtx + (c->gap * seq2_len);
    while (i < end_row) {
        /** Invariants block */
        cur_seq1 = seq1->begin[i];
        const_val = cm_calc_cost (c->cost, cur_seq1, c->gap, c->lcm);
        const_val_tail = (cm_get_tail_cost (c))[cur_seq1];
        /* Conceptually,
           alg_row = cm_get_precal_row (precalcMtx, cur_seq1, seq2_len);
        */
        alg_row = precalcMtx + (cur_seq1 * seq2_len);
        /* Align! */
        algn_fill_first_cell (curRow, prevRow[0], dirMtx, alg_row[0]);
        algn_fill_row (curRow, prevRow, gap_row, alg_row, dirMtx, const_val, 1, seq2_len - 1);
        algn_fill_last_column (curRow, prevRow, const_val_tail, seq2_len - 1, dirMtx);
        /** Invariants block */
        tmp = curRow;
        curRow = prevRow;
        prevRow = tmp;
        i++;
        dirMtx += seq2_len;
    }
    return (curRow);
}

/* Simiilar to the previous but when no barriers are set */
static inline int
algn_fill_plane (const seq_p seq1, int *precalcMtx, int seq1_len, 
                 int seq2_len, int *curRow, DIRECTION_MATRIX *dirMtx, const cost_matrices_2d_p c) {
    int i;
    const int *alg_row;
    int const_val, const_val_tail, *newNWMtx, *tmp;
    const int *gap_row, *first_gap_row;
    int gapcode;
    /* A precalculated cost of a gap aligned with each base in the array */
    gapcode = cm_get_gap_2d (c);
    gap_row = cm_get_precal_row (precalcMtx, gapcode, seq2_len);
    first_gap_row = cm_get_precal_row (precalcMtx, 0, seq2_len);
    newNWMtx = curRow;
    curRow[0] = 0;
    dirMtx[0] = ALIGN;
    if (DEBUG_COST_M) {
        printf ("%d\t", curRow[0]);
    }
    if (DEBUG_DIR_M) {
        printf ("A\t");
    }
    /* We fill the first row to start with */
    for (i = 1; i < seq2_len; i++) {
        curRow[i] = curRow[i - 1] + first_gap_row[i];
        dirMtx[i] = INSERT;
        if (DEBUG_COST_M) {
            printf ("%d\t", curRow[i]);
        }
        if (DEBUG_DIR_M) {
            printf ("I\t");
        }
    }
    if (DEBUG_DIR_M || DEBUG_COST_M) {
        printf ("\n");
    }
    curRow += seq2_len;
    /* Now we fill the rest of the matrix */
    for (i = 1, dirMtx += seq2_len; i < seq1_len; i++, dirMtx += seq2_len) {
        const_val_tail = (cm_get_tail_cost(c))[seq_get_element(seq1, i)]; // get tail cost in c at pointer
                                                                // at position i in seq1
        const_val = cm_calc_cost (c->cost, seq_get_element(seq1, i), c->gap, c->lcm);
        alg_row = cm_get_precal_row (precalcMtx, seq_get_element (seq1, i), seq2_len);
        algn_fill_full_row (curRow, newNWMtx, gap_row, alg_row, dirMtx, const_val, 
                            const_val_tail, seq2_len);
        /* We swap curRow and newNWMtx for the next round */
        tmp      = curRow;
        curRow    = newNWMtx;
        newNWMtx = tmp;
    }
    return (newNWMtx[seq2_len - 1]);
}

static inline int *
choose_other (int *compare, int *a, int *b) {
    if (a == compare) return b;
    else return a;
}

static inline int
algn_fill_plane_2 (const seq_p seq1, int *precalcMtx, int seq1_len, int seq2_len, int *curRow, 
                   DIRECTION_MATRIX *dirMtx, const cost_matrices_2d_p c, 
                   int width, int height, int dwidth_height) {
    int *next_row;
    int *next_prevRow;
    int *a, *b;
    int const *gap_row;
    int start_row, final_row, start_column, length;
    DIRECTION_MATRIX *to_go_dirMtx;
    width = width + dwidth_height;
    if (width > seq2_len) width = seq2_len; // width is at most seq2_len
    height = height + dwidth_height;
    if (height > seq1_len) height = seq1_len; // likewise, height is at most seq1_len
    a = curRow;
    b = curRow + seq2_len;
    gap_row = cm_get_precal_row (precalcMtx, 0, seq2_len); // We want the first horizontal row

    /* We have to consider three cases in this new alignment procedure (much
     * cleaner than the previous):
     *
     * Case 1:
     * If seq1_len >= 1.5 * seq2_len, there is no point in using the
     * barriers. Rather, we fill the full matrix in one shot */
    if (seq1_len >= 1.5 * seq2_len) // deleted a bunch of casts here
        return (algn_fill_plane (seq1, precalcMtx, seq1_len, seq2_len, curRow, dirMtx, c));
    /* Case 2:
     * There are no full rows to be filled, therefore we have to break the
     * procedure into two different subsets */
    // subset 1:
    else if (2 * height < seq1_len) {
        algn_fill_first_row (a, dirMtx, width, gap_row);
        start_row = 1;
        final_row = height;
        start_column = 0;
        length = width + 1;
        to_go_dirMtx = dirMtx + (start_row * seq2_len);
        /* Now we fill that space */
        next_row = algn_fill_extending_right (seq1, precalcMtx, seq1_len, seq2_len, b, a, 
                                              to_go_dirMtx, c, start_row, final_row, length);
        next_prevRow = choose_other (next_row, a, b);
        /* Next group */
        start_row = final_row;
        final_row = seq1_len - (height - 1);
        start_column = 1;
        length = width + height;
        to_go_dirMtx = dirMtx + (start_row * seq2_len);
        next_row = algn_fill_extending_left_right (seq1, precalcMtx, seq1_len, 
                                                   seq2_len, next_row, next_prevRow, to_go_dirMtx, c, start_row, 
                                                   final_row, start_column, length);
        next_prevRow = choose_other (next_row, a, b);
        /* The final group */
        start_row = final_row;
        final_row = seq1_len;
        length = length - 2;
        start_column = seq2_len - length;
        to_go_dirMtx = dirMtx + (start_row * seq2_len);
        next_row = algn_fill_extending_left (seq1, precalcMtx, seq1_len, seq2_len, 
                                             next_row, next_prevRow, to_go_dirMtx, c, start_row, final_row, 
                                             start_column, length);
        next_prevRow = choose_other (next_row, a, b);
    }
    /* Case 3: (final case)
     * There is a block in the middle with full rows that have to be filled
     */
    else {
        /* We will simplify this case even further: If the size of the leftover
         * is too small, don't use the barriers at all, just fill it all up
         */
        // subset 2:
        if (8 >= (seq1_len - height)) {
            return (algn_fill_plane (seq1, precalcMtx, seq1_len, seq2_len, curRow, dirMtx, c));
        // subset 3:
        } else {
            algn_fill_first_row (curRow, dirMtx, width, gap_row);
            start_row = 1;
            final_row = (seq2_len - width) + 1;
            start_column = 0;
            length = width + 1;
            to_go_dirMtx = dirMtx + (seq2_len * start_row);
            next_row = algn_fill_extending_right (seq1, precalcMtx, seq1_len, seq2_len, b, a, 
                                                  to_go_dirMtx, c, start_row, final_row, length);
            next_prevRow = choose_other (next_row, a, b);
            start_row = final_row;
            final_row = seq1_len - (seq2_len - width) + 1;
            length = seq2_len;
            to_go_dirMtx = dirMtx + (seq2_len * start_row);
            next_row = algn_fill_no_extending (seq1, precalcMtx, seq1_len, seq2_len, 
                                               next_row, next_prevRow, to_go_dirMtx, c, start_row, 
                                               final_row);
            next_prevRow = choose_other (next_row, a, b);
            start_row = final_row;
            final_row = seq1_len;
            start_column = 1;
            length = seq2_len - 1;
            to_go_dirMtx = dirMtx + (seq2_len * start_row);
            next_row = algn_fill_extending_left (seq1, precalcMtx, seq1_len, seq2_len, 
                                                 next_row, next_prevRow, to_go_dirMtx, 
                                                 c, start_row, final_row, start_column, length);
            next_prevRow = choose_other (next_row, a, b);
        }
    }
    return (next_prevRow[seq2_len - 1]);
}
/******************************************************************************/

/******************************************************************************/
/*                         Pairwise Affine Alignment                          */
/******************************************************************************/
/*
 *
 * WARNING! This is a copy of the pairwise standard alignment, modified slightly
 * for the affine case. This is for performance issues! so beware, any change
 * here must also go there.
 */

#define algn_assign_dirMtx(dirMtx, pos, v) dirMtx[pos] = dirMtx[pos] | v

static inline void
algn_fill_row_affine (int *curRow, const int *prevRow, const int *gap_row, 
                   const int *alg_row, DIRECTION_MATRIX *dirMtx, int c, int cprev, int st, 
                   int end, int *dncurRow, const int *pdncurRow, int *htcurRow, int open_gap) {
    int i, tmp1, tmp2, tmp3, tmp4, tmp5;

    for (i = st; i <= end; i++) {
        /* try align with substitution */
#ifdef DEBUG_ALL_ASSERTIONS
        assert ((curRow + i) < _algn_max_matrix);
        assert ((prevRow + i) < _algn_max_matrix);
        assert ((dirMtx + i) < _algn_max_direction);
        assert ((dncurRow + i) < _algn_max_matrix);
        assert ((pdncurRow + i) < _algn_max_matrix);
        assert ((htcurRow + i) < _algn_max_matrix);
#endif
        dirMtx[i] = 0;
        { /* We deal with the difficultness of using an opening gap as
             another DIRECTION_MATRIX */
            if ((0 == cprev) && (0 != c)) {
                tmp1 = pdncurRow[i] + open_gap + c;
                tmp4 = prevRow[i] + open_gap + c;
            }
            else if ((0 != cprev) && (0 == c)) {
                tmp1 = pdncurRow[i] + open_gap + c;
                tmp4 = prevRow[i];
            }
            else {
                tmp1 = pdncurRow[i] + c;
                tmp4 = prevRow[i] + open_gap + c;
            }

            if ((0 == gap_row[i - 1]) && (0 != gap_row[i])) {
                tmp5 = htcurRow[i - 1] + open_gap + gap_row[i];
                tmp2 = curRow[i - 1] + open_gap + gap_row[i];
            }
            else if ((0 != gap_row[i - 1]) && (0 == gap_row[i])) {
                tmp5 = htcurRow[i - 1] + open_gap + gap_row[i];
                tmp2 = curRow[i - 1];
            }
            else {
                tmp2 = curRow[i - 1] + open_gap + gap_row[i];
                tmp5 = htcurRow[i - 1] + gap_row[i];
            }

            if ((((0 == gap_row[i]) && (0 != c)) ||
                    ((0 != gap_row[i]) && (0 == c))) &&
                    ((0 == gap_row[i - 1]) || (0 == cprev)))
                tmp3 = prevRow[i - 1] + open_gap + alg_row[i];
            else
                tmp3 = prevRow[i - 1] + alg_row[i];
        }
        if (tmp1 < tmp4)
            algn_assign_dirMtx(dirMtx, i, DELETE_V);
        else {
            algn_assign_dirMtx(dirMtx, i, ALIGN_V);
            tmp1 = tmp4;
        }

        if (tmp2 <= tmp5) {
            algn_assign_dirMtx(dirMtx, i, ALIGN_H);
        }
        else {
            tmp2 = tmp5;
            algn_assign_dirMtx(dirMtx, i, INSERT_H);
        }
        dncurRow[i] = tmp1;
        htcurRow[i] = tmp2;
        /* check whether insertion is better */
        /* This option will allow all the possible optimal paths to be stored
         * concurrently on the same backtrace matrix. This is important for the
         * sequences being able to choose the appropriate direction while
         * keeping the algorithm that assumes that seq2 is at most as long as seq1.
         * */
        if (tmp1 < tmp3) {
            if (tmp1 < tmp2) {
                curRow[i] = tmp1;
                algn_assign_dirMtx(dirMtx, i, DELETE);
            }
            else if (tmp2 < tmp1) {
                curRow[i] = tmp2;
                algn_assign_dirMtx(dirMtx, i, INSERT);
            }
            else {
                curRow[i] = tmp2;
                algn_assign_dirMtx(dirMtx, i, (DELETE | INSERT));
            }
        }
        else if (tmp3 < tmp1) {
            if (tmp3 < tmp2) {
                curRow[i] = tmp3;
                algn_assign_dirMtx(dirMtx, i, ALIGN);
            }
            else if (tmp2 < tmp3) {
                curRow[i] = tmp2;
                algn_assign_dirMtx(dirMtx, i, INSERT);
            }
            else {
                curRow[i] = tmp2;
                algn_assign_dirMtx(dirMtx, i, ALIGN | INSERT);
            }
        }
        else { /* tmp3 == tmp1 */
            if (tmp3 < tmp2) {
                curRow[i] = tmp3;
                algn_assign_dirMtx(dirMtx, i, ALIGN | DELETE);
            }
            else if (tmp2 < tmp3) {
                curRow[i] = tmp2;
                algn_assign_dirMtx(dirMtx, i, INSERT);
            }
            else {
                curRow[i] = tmp2;
                algn_assign_dirMtx(dirMtx, i, DELETE | INSERT | ALIGN);
            }
        }
        if (DEBUG_DIR_M) {
            /* Print the alignment matrix */
            if (INSERT & dirMtx[i])
                printf ("I");
            if (DELETE & dirMtx[i])
                printf ("D");
            if (ALIGN & dirMtx[i])
                printf ("A");
            printf ("\t");
        }
        if (DEBUG_COST_M) {
            /* Print the cost matrix */
            printf ("(%d, %d, %d)\t", curRow[i], htcurRow[i], dncurRow[i]);
            fflush (stdout);
        }
    }
    if (DEBUG_DIR_M) {
        printf ("\n");
        fflush (stdout);
    }
    return;
}

static inline void
algn_fill_ukk_right_cell_affine (int *curRow, const int *prevRow, const int *gap_row, 
                              const int *alg_row, DIRECTION_MATRIX *dirMtx, int c, int cprev, 
                              int pos, int *dncurRow, int *htcurRow, int open_gap) {
    int tmp2, tmp3, tmp4;
    /* try align with substitution */
#ifdef DEBUG_ALL_ASSERTIONS
        assert ((curRow + pos) < _algn_max_matrix);
        assert ((prevRow + pos) < _algn_max_matrix);
        assert ((dirMtx + pos) < _algn_max_direction);
        assert ((htcurRow + pos) < _algn_max_matrix);
#endif
    dirMtx[pos] = 0;
    { /* Affine gap difficultness */
        if ((0 != gap_row[pos - 1]) && (0 == gap_row[pos]))
            tmp2 = curRow[pos - 1];
        else
            tmp2 = curRow[pos - 1] + open_gap + gap_row[pos];

        if (((0 == gap_row[pos - 1]) && (0 != gap_row[pos])) ||
            ((0 != gap_row[pos - 1]) && (0 == gap_row[pos])))
            tmp4 = htcurRow[pos - 1] + open_gap + gap_row[pos];
        else
            tmp4 = htcurRow[pos - 1] + gap_row[pos];

        if ((((0 == gap_row[pos]) && (0 != c)) ||
                ((0 != gap_row[pos]) && (0 == c))) &&
                ((0 == gap_row[pos - 1]) || (0 == cprev)))
            tmp3 = prevRow[pos - 1] + open_gap + alg_row[pos];
        else
            tmp3 = prevRow[pos - 1] + alg_row[pos];
    }
    if (tmp2 <= tmp4)
        algn_assign_dirMtx(dirMtx, pos, ALIGN_H);
    else {
        tmp2 = tmp4;
        algn_assign_dirMtx(dirMtx, pos, INSERT_H);
    }
    htcurRow[pos] = tmp2;
    dncurRow[pos] = INT_MAX;
    /* check whether insertion is better */
    if (tmp2 < tmp3) {
        curRow[pos] = tmp2;
        algn_assign_dirMtx(dirMtx, pos, (INSERT));
    }
    else if (tmp3 < tmp2) {
        curRow[pos] = tmp3;
        algn_assign_dirMtx(dirMtx, pos, (ALIGN));
    }
    else {
        curRow[pos] = tmp3;
        algn_assign_dirMtx(dirMtx, pos, (INSERT | ALIGN));
    }
    if (DEBUG_DIR_M) {
        /* Print the alignment matrix */
        if (INSERT & dirMtx[pos])
            printf ("I");
        if (DELETE & dirMtx[pos])
            printf ("D");
        if (ALIGN & dirMtx[pos])
            printf ("A");
        printf ("\t");
    }
    if (DEBUG_COST_M) {
        /* Print the cost matrix */
        printf ("(%d, %d)\t", curRow[pos], htcurRow[pos]);
    }
    if (DEBUG_DIR_M || DEBUG_COST_M)
        printf ("\n");
    return;
}

static inline void
algn_fill_ukk_left_cell_affine (int *curRow, const int *prevRow, const int *gap_row, 
                             const int *alg_row, DIRECTION_MATRIX *dirMtx, int c, int cprev, 
                             int pos, int *dncurRow, int *pdncurRow, int *htcurRow, int open_gap) {
    int tmp1, tmp3, tmp5;
    /* try align with substitution */
#ifdef DEBUG_ALL_ASSERTIONS
        assert ((curRow + pos) < _algn_max_matrix);
        assert ((prevRow + pos) < _algn_max_matrix);
        assert ((dirMtx + pos) < _algn_max_direction);
        assert ((dncurRow + pos) < _algn_max_matrix);
        assert ((pdncurRow + pos) < _algn_max_matrix);
#endif
    dirMtx[pos] = 0;
    { /* Affine gap difficultness */
        if ((0 != cprev) && (0 == c))
            tmp1 = prevRow[pos];
        else
            tmp1 = prevRow[pos] + open_gap + c;

        if (((0 == cprev) && (0 != c)) ||
            ((0 != cprev) && (0 == c)))
            tmp5 = pdncurRow[pos] + open_gap + c;
        else
            tmp5 = pdncurRow[pos] + c;

        if ((((0 == gap_row[pos]) && (0 != c)) ||
                ((0 != gap_row[pos]) && (0 == c))) &&
                    ((0 == gap_row[pos - 1]) || (0 == cprev)))
            tmp3 = prevRow[pos - 1] + open_gap + alg_row[pos];
        else
            tmp3 = prevRow[pos - 1] + alg_row[pos];
    }
    if (tmp1 <= tmp5)
        algn_assign_dirMtx(dirMtx, pos, ALIGN_V);
    if (tmp5 < tmp1) {
        algn_assign_dirMtx(dirMtx, pos, DELETE_V);
        tmp1 = tmp5;
    }
    dncurRow[pos] = tmp1;
    htcurRow[pos] = INT_MAX;
        if (tmp1 < tmp3) {
            curRow[pos] = tmp1;
            algn_assign_dirMtx(dirMtx, pos, (DELETE));
        }
        else if (tmp3 < tmp1) {
            curRow[pos] = tmp3;
            algn_assign_dirMtx(dirMtx, pos, (ALIGN));
        }
        else {
            curRow[pos] = tmp1;
            algn_assign_dirMtx(dirMtx, pos, (ALIGN | DELETE));
        }
    if (DEBUG_DIR_M) {
        /* Print the alignment matrix */
        if (INSERT & dirMtx[pos])
            printf ("I");
        if (DELETE & dirMtx[pos])
            printf ("D");
        if (ALIGN & dirMtx[pos])
            printf ("A");
        printf ("\t");
    }
    if (DEBUG_COST_M) {
        /* Print the cost matrix */
        printf ("(%d, ,%d)\t", curRow[pos], dncurRow[pos]);
    }
    return;
}

static inline void
algn_fill_last_column_affine (int *curRow, const int *prevRow, int tlc, int tlcprev, 
                           int l, DIRECTION_MATRIX *dirMtx, int *dncurRow, const int *pdncurRow, int open_gap) {
    int cst, tmp2;
#ifdef DEBUG_ALL_ASSERTIONS
        assert ((curRow + l) < _algn_max_matrix);
        assert ((prevRow + l) < _algn_max_matrix);
        assert ((dirMtx + l) < _algn_max_direction);
        assert ((dncurRow + l) < _algn_max_matrix);
        assert ((pdncurRow + l) < _algn_max_matrix);
#endif
    tmp2 = prevRow[l] + tlc + open_gap;
    { /* Affine gap difficultness */
        if (((0 == tlcprev) && (0 != tlc)) ||
            ((0 != tlcprev) && (0 == tlc)))
            cst = pdncurRow[l] + open_gap + tlc;
        else
            cst = pdncurRow[l] + tlc;
    }
    if (cst < tmp2)
        algn_assign_dirMtx(dirMtx, l, DELETE_V);
    else {
        cst = tmp2;
        algn_assign_dirMtx(dirMtx, l, ALIGN_V);
    }
    dncurRow[l] = cst;
    if (cst < curRow[l]) {
        curRow[l] = cst;
        algn_assign_dirMtx(dirMtx, l, (DELETE));
    }
    else if (cst == curRow[l])
        algn_assign_dirMtx(dirMtx, l, DELETE);
    return;
}

static inline void
algn_fill_full_row_affine (int *curRow, const int *prevRow, const int *gap_row, 
                        const int *alg_row, DIRECTION_MATRIX *dirMtx, int c, int cprev, int tlc, 
                        int tlcprev, int l, int *dncurRow, const int *pdncurRow, int *htcurRow, 
                        int open_gap) {
    /* first entry is delete */
    htcurRow[0] = INT_MAX;
    curRow[0] += c;
    dirMtx[0] = DELETE | DELETE_V;
    dncurRow[0] = c + pdncurRow[0];
    if (DEBUG_COST_M)
        printf ("%d\t", curRow[0]);
    if (DEBUG_DIR_M)
        printf ("D\t");
    algn_fill_row_affine (curRow, prevRow, gap_row, alg_row, dirMtx, c, cprev, 1, l - 1, 
                       dncurRow, pdncurRow, htcurRow, open_gap);
    algn_fill_last_column_affine (curRow, prevRow, tlc, tlcprev, l - 1, dirMtx, dncurRow, pdncurRow, open_gap);
    return;
}

void
algn_fill_first_row_affine (int *curRow, DIRECTION_MATRIX *dirMtx, int len, int const *gap_row, 
                         int *dncurRow, int *htcurRow, int open_gap) {
    int i;
    /* We fill the first cell to start with */
    curRow[0] = open_gap;
    dncurRow[0] = htcurRow[0] = INT_MAX;
    dirMtx[0] = ALIGN | ALIGN_V | ALIGN_H;
    /* Now the rest of the row */
    if (DEBUG_DIR_M)
        printf ("A\t");
    if (DEBUG_COST_M)
        printf ("%d\t", curRow[0]);
    for (i = 1; i < len; i++) {
        dncurRow[i] = INT_MAX;
        curRow[i] = curRow[i - 1] + gap_row[i];
        dirMtx[i] = INSERT | (INSERT_H);
        if (DEBUG_DIR_M)
            printf ("I\t");
        if (DEBUG_COST_M)
            printf ("%d\t", curRow[i]);
    }
    return;
}

void
algn_fill_first_cell_affine (int *curRow, int prevRow, DIRECTION_MATRIX *dirMtx, int gap, int *dncurRow, 
                          int *pdncurRow, int *htcurRow) {
    htcurRow[0] = INT_MAX;
    curRow[0] += gap;
    *dirMtx = DELETE | DELETE_V;
    dncurRow[0] = gap + pdncurRow[0];
    if (DEBUG_DIR_M)
        printf ("D\t");
    if (DEBUG_COST_M)
        printf ("%d\t", *curRow);
    return;
}

/* In the following three functions, we maintain the following invariants in
 * each loop:
 * 1. curRow is a row that has not been filled and is the next to be.
 * 4. dirMtx is the current row of the direction matrix
 * 2. prevRow is the previous row, located right above curRow, which has been filled
 *    already.
 * 3. i is the number of the row of curRow in its containing matrix
 * 5. gap_row is the cost of aligning each base of seq2 with a gap. This is
 *    constant for all the loop.
 * 6. cur_seq1 is the i'th base of seq1
 * 7. const_val is the cost of cur_seq1 aligned with a gap
 * 8. alg_row is the vector of costs of aligning seq2 with cur_seq1
 */

int *
algn_fill_extending_right_affine (const seq_p seq1, int *precalcMtx, int seq1_len, 
                               int seq2_len, int *curRow, int *prevRow, 
                               DIRECTION_MATRIX *dirMtx, const cost_matrices_2d_p c, 
                               int start_row, int end_row, int len, 
                               int *dncurRow, int *pdncurRow, int *htcurRow, int open_gap) {
    int i;
    int *tmp, *tmp1, cur_seq1, const_val, prev_seq1, prev_const_val;
    const int *gap_row, *alg_row;
    /** Invariants block
     *  len is the number of items in the row to be filled 
     */
    i = start_row;
    /* This is what we will perform conceptually, I will stop using the
     * cm_get_precal_row function to speed this up a little bit
     * gap_row = cm_get_precal_row (precalcMtx, cm_get_gap (c), seq2_len);
    */
    gap_row = precalcMtx + (c->gap * seq2_len);
    while (i < end_row) {
        /** Invariants block */
        assert (i > 0);
        prev_seq1 = seq1->begin[i - 1];
        cur_seq1 = seq1->begin[i];
        const_val = cm_calc_cost (c->cost, cur_seq1, c->gap, c->lcm);
        prev_const_val = cm_calc_cost (c->cost, prev_seq1, c->gap, c->lcm);
        /* This is conceptually what we do in the next line
         * alg_row = cm_get_precal_row (precalcMtx, cur_seq1, seq2_len);
         */
        alg_row = precalcMtx + (cur_seq1 * seq2_len);
        /* Align! */
        algn_fill_first_cell_affine (curRow, prevRow[0], dirMtx, alg_row[0], dncurRow, pdncurRow, htcurRow);
        algn_fill_row_affine (curRow, prevRow, gap_row, alg_row, dirMtx, const_val, 
                           prev_const_val, 1, len - 2, dncurRow, pdncurRow, htcurRow, open_gap);
        algn_fill_ukk_right_cell_affine (curRow, prevRow, gap_row, alg_row, dirMtx, 
                                      const_val, prev_const_val, len - 1, dncurRow, htcurRow, open_gap);
        /** Invariants block */
        tmp = curRow;
        tmp1 = dncurRow;
        curRow = prevRow;
        dncurRow = pdncurRow;
        prevRow = tmp;
        pdncurRow = tmp1;
        i++;
        dirMtx += seq2_len;
        len++;
        curRow[0] = prevRow[0];
    }
    return (curRow);
}

int *
algn_fill_extending_left_right_affine (const seq_p seq1, int *precalcMtx, int seq1_len, 
                                    int seq2_len,  int *curRow, int *prevRow, 
                                    DIRECTION_MATRIX *dirMtx, const cost_matrices_2d_p c, 
                                    int start_row, int end_row, int start_column, int len, 
                                    int *dncurRow, int *pdncurRow, int *htcurRow, int open_gap) {
    int i;
    int *tmp, *tmp1, cur_seq1, const_val, prev_seq1, prev_const_val;
    const int *gap_row, *alg_row;
    /** Invariants block
     * len is the number of cells to fill in the current row minus 1
     * start_column is the first cell to fill in the row */
    i = start_row;
    /* Conceptually,
       gap_row = cm_get_precal_row (precalcMtx, cm_get_gap (c), seq2_len);
    */
    gap_row = precalcMtx + (c->gap * seq2_len);
    len--;
    while (i < end_row) {
        /** Invariants block */
        assert (i > 0);
        prev_seq1 = seq1->begin[i - 1];
        cur_seq1 = seq1->begin[i];
        const_val = cm_calc_cost (c->cost, cur_seq1, c->gap, c->lcm);
        prev_const_val = cm_calc_cost (c->cost, prev_seq1, c->gap, c->lcm);
        /* Conceptually,
         * alg_row = cm_get_precal_row (precalcMtx, cur_seq1, seq2_len);
         */
        alg_row = precalcMtx + (cur_seq1 * seq2_len);
        /* Align! */
        algn_fill_ukk_left_cell_affine (curRow, prevRow, gap_row, alg_row, dirMtx, const_val, 
                                     prev_const_val, start_column, dncurRow, pdncurRow, htcurRow, open_gap);
        algn_fill_row_affine (curRow, prevRow, gap_row, alg_row, dirMtx, const_val, 
                           prev_const_val, start_column + 1, start_column + (len - 2), 
                           dncurRow, pdncurRow, htcurRow, open_gap);
        algn_fill_ukk_right_cell_affine (curRow, prevRow, gap_row, alg_row, dirMtx, const_val, 
                                      prev_const_val, start_column + len - 1, dncurRow, htcurRow, open_gap);
        /** Invariants block */
        tmp = curRow;
        tmp1 = dncurRow;
        curRow = prevRow;
        dncurRow = pdncurRow;
        prevRow = tmp;
        pdncurRow = tmp1;
        i++;
        dirMtx += seq2_len;
        start_column++;
    }
    return (curRow);
}

int *
algn_fill_extending_left_affine (const seq_p seq1, int *precalcMtx, int seq1_len, 
                              int seq2_len,  int *curRow, int *prevRow, 
                              DIRECTION_MATRIX *dirMtx, const cost_matrices_2d_p c, 
                              int start_row, int end_row, int start_column, int len, 
                              int *dncurRow, int *pdncurRow, int *htcurRow, int open_gap) {
    int i;
    int *tmp, *tmp1, cur_seq1, const_val, prev_seq1, prev_const_val, 
        const_val_tail, prev_const_val_tail;
    const int *gap_row, *alg_row;
    /** Invariants block
     *  start_column is the first cell to fill in the row
     *  len is the number of cells to fill in the current row minus 1 
     */
    i = start_row;
    /* Conceptually,
     * gap_row = cm_get_precal_row (precalcMtx, cm_get_gap (c), seq2_len);
     */
    gap_row = precalcMtx + (c->gap * seq2_len);
    while (i < end_row) {
        /** Invariants block */
        assert (i > 0);
        prev_seq1 = seq1->begin[i - 1];
        cur_seq1 = seq1->begin[i];
        prev_const_val = cm_calc_cost (c->cost, prev_seq1, c->gap, c->lcm);
        const_val = cm_calc_cost (c->cost, cur_seq1, c->gap, c->lcm);
        const_val_tail = (cm_get_tail_cost (c))[cur_seq1];
        prev_const_val_tail = (cm_get_tail_cost (c))[prev_seq1];
        /* Conceptually,
         * alg_row = cm_get_precal_row (precalcMtx, cur_seq1, seq2_len);
         */
        alg_row = precalcMtx + (cur_seq1 * seq2_len);
        /* Align! */
        algn_fill_ukk_left_cell_affine (curRow, prevRow, gap_row, alg_row, dirMtx, const_val, 
                                     prev_const_val, start_column, dncurRow, pdncurRow, htcurRow, open_gap);
        algn_fill_row_affine (curRow, prevRow, gap_row, alg_row, dirMtx, const_val, prev_const_val, 
                           start_column + 1, start_column + len - 1, dncurRow, pdncurRow, htcurRow, 
                           open_gap);
        algn_fill_last_column_affine (curRow, prevRow, const_val_tail, prev_const_val_tail, 
                                   start_column + len - 1, dirMtx, dncurRow, pdncurRow, open_gap);
        /** Invariants block */
        tmp = curRow;
        tmp1 = dncurRow;
        curRow = prevRow;
        dncurRow = pdncurRow;
        prevRow = tmp;
        pdncurRow = tmp1;
        i++;
        dirMtx += seq2_len;
        start_column++;
        len--;
    }
    if (DEBUG_COST_M) {
        printf ("ALIGNALL gap cost\n");
        fflush (stdout);
        for (i = 0; i < seq2_len; i++) {
            printf ("%d\t", gap_row[i]);
            fflush (stdout);
        }
        fflush (stdout);
    }

    return (curRow);
}

int *
algn_fill_no_extending_affine (const seq_p seq1, int *precalcMtx, int seq1_len, 
                            int seq2_len,  int *curRow, int *prevRow, 
                            DIRECTION_MATRIX *dirMtx, const cost_matrices_2d_p c, 
                            int start_row, int end_row, int *dncurRow, int *pdncurRow, int *htcurRow, int open_gap) {
    int i;
    int *tmp, cur_seq1, const_val, const_val_tail, prev_seq1, prev_const_val, prev_const_val_tail, *tmp1;
    const int *gap_row, *alg_row;
    /** Invariants block */
    i = start_row;
    /* Conceptually,
     * gap_row = cm_get_precal_row (precalcMtx, cm_get_gap (c), seq2_len);
     */
    gap_row = precalcMtx + (c->gap * seq2_len);
    while (i < end_row) {
        /** Invariants block */
        assert (i > 0);
        prev_seq1 = seq1->begin[i - 1];
        cur_seq1 = seq1->begin[i];
        const_val = cm_calc_cost (c->cost, cur_seq1, c->gap, c->lcm);
        prev_const_val = cm_calc_cost (c->cost, prev_seq1, c->gap, c->lcm);
        const_val_tail = (cm_get_tail_cost (c))[cur_seq1];
        prev_const_val_tail = (cm_get_tail_cost (c))[prev_seq1];
        /* Conceptually,
         * alg_row = cm_get_precal_row (precalcMtx, cur_seq1, seq2_len);
         */
        alg_row = precalcMtx + (cur_seq1 * seq2_len);
        /* Align! */
        algn_fill_first_cell_affine (curRow, prevRow[0], dirMtx, open_gap, dncurRow, pdncurRow, htcurRow);
        algn_fill_row_affine (curRow, prevRow, gap_row, alg_row, dirMtx, const_val, 
                           prev_const_val, 1, seq2_len - 1, dncurRow, pdncurRow, htcurRow, open_gap);
        algn_fill_last_column_affine (curRow, prevRow, const_val_tail, 
                                   prev_const_val_tail, seq2_len - 1, dirMtx, dncurRow, 
                                   pdncurRow, open_gap);
        /** Invariants block */
        tmp = curRow;
        tmp1 = dncurRow;
        curRow = prevRow;
        dncurRow = pdncurRow;
        prevRow = tmp;
        pdncurRow = tmp1;
        i++;
        dirMtx += seq2_len;
    }
    return (curRow);
}

/* SicurRowilar to the previous but when no barriers are set */
static inline int
algn_fill_plane_affine (const seq_p seq1, int *precalcMtx, int seq1_len, 
                     int seq2_len, int *curRow, DIRECTION_MATRIX *dirMtx, const cost_matrices_2d_p c, 
                     int *dncurRow, int *htcurRow, int open_gap) {
    int i;
    const int *alg_row;
    int const_val, const_val_tail, prev_const_val, prev_const_val_tail, *newNWMtx, *tmp, *tmp1, *pdncurRow;
    const int *gap_row, *first_gap_row;
    int gapcode;
    /* A precalculated cost of a gap aligned with each base in the array */
    gapcode = cm_get_gap_2d (c);
    gap_row = cm_get_precal_row (precalcMtx, gapcode, seq2_len);
    first_gap_row = cm_get_precal_row (precalcMtx, 0, seq2_len);
    newNWMtx = curRow;
    pdncurRow = dncurRow;
    curRow[0] = open_gap;
    dirMtx[0] = ALIGN | ALIGN_H | ALIGN_V;
    htcurRow[0] = INT_MAX;
    dncurRow[0] = INT_MAX;
    if (DEBUG_COST_M)
        printf ("%d\t", curRow[0]);
    if (DEBUG_DIR_M)
        printf ("A\t");
    /* We fill the first row to start with */
    for (i = 1; i < seq2_len; i++) {
        dncurRow[i] = INT_MAX;
        curRow[i] = curRow[i - 1] + first_gap_row[i];
        dirMtx[i] = INSERT | INSERT_H;
        if (DEBUG_COST_M) {
            printf ("%d\t", curRow[i]);
            fflush (stdout);
        }
        if (DEBUG_DIR_M)
            printf ("I\t");
    }
    curRow += seq2_len;
    curRow[0] = newNWMtx[0];
    newNWMtx[0] = 0;
    if (DEBUG_DIR_M || DEBUG_COST_M) {
        printf ("\n");
        fflush (stdout);
    }
    dncurRow += seq2_len;
    /* Now we fill the rest of the matrix */
    for (i = 1, dirMtx += seq2_len; i < seq1_len; i++, dirMtx += seq2_len) {
        prev_const_val_tail = (cm_get_tail_cost (c))[seq_get_element(seq1, i - 1)];
        prev_const_val = cm_calc_cost (c->cost, seq_get_element(seq1, i - 1), c->gap, c->lcm);
        const_val_tail = (cm_get_tail_cost (c))[seq_get_element(seq1, i)];
        const_val = cm_calc_cost (c->cost, seq_get_element(seq1, i), c->gap, c->lcm);
        alg_row = cm_get_precal_row (precalcMtx, seq_get_element (seq1, i), seq2_len);
        algn_fill_full_row_affine (curRow, newNWMtx, gap_row, alg_row, dirMtx, const_val, 
                                prev_const_val, const_val_tail, prev_const_val_tail, seq2_len, 
                                dncurRow, pdncurRow, htcurRow, open_gap);
        if (DEBUG_COST_M) {
            printf ("\n");
            fflush (stdout);
        }
        /* We swap curRow and newNWMtx for the next round */
        tmp = curRow;
        tmp1 = dncurRow;
        curRow = newNWMtx;
        dncurRow = pdncurRow;
        newNWMtx = tmp;
        pdncurRow = tmp1;
        curRow[0] = newNWMtx[0];
    }
    return (newNWMtx[seq2_len - 1]);
}

static inline void
algn_choose_affine_other (int *next_row, int *curRow, int **next_dncurRow, 
                       int **next_pdncurRow, int *dncurRow, int *pdncurRow) {
    if (next_row == curRow) {
        *next_dncurRow = dncurRow;
        *next_pdncurRow = pdncurRow;
    }
    else {
        *next_dncurRow = pdncurRow;
        *next_pdncurRow = dncurRow;
    }
    return;
}

#define ALIGN_TO_ALIGN 1
#define ALIGN_TO_VERTICAL 2
#define ALIGN_TO_HORIZONTAL 4
#define ALIGN_TO_DIAGONAL 8
#define BEGIN_BLOCK 16
#define END_BLOCK 32
#define BEGIN_VERTICAL 64
#define END_VERTICAL 128
#define BEGIN_HORIZONTAL 256
#define END_HORIZONTAL 512
#define DO_ALIGN 1024
#define DO_VERTICAL 2048
#define DO_HORIZONTAL 4096
#define DO_DIAGONAL 8192
// DO_DIAGONAL MUST BE THE LAST ONE

#define TMPGAP 16
#define NTMPGAP 15

#define LOR_WITH_DIRECTION_MATRIX(mask, direction_matrix) direction_matrix |= mask

static inline int
HAS_GAP_EXTENSION (SEQT base, const cost_matrices_2d_p c) {
    return (cm_calc_cost(c->cost, base, c->gap, c->lcm));
}

static inline int
HAS_GAP_OPENING (SEQT prev, SEQT curr, int gap, int gap_open) {
    if ((!(gap & prev)) && (gap & curr)) return 0;
    else return gap_open;
}

// TODO: is this used?
static inline void
FILL_EXTEND_HORIZONTAL_NOBT (int sj_horizontal_extension, int sj_gap_extension, int sj_gap_opening, int j, 
                             int *extend_horizontal, const cost_matrices_2d_p c, 
                             const int *close_block_diagonal) {
    int ext_cost, open_cost;
    ext_cost = extend_horizontal[j - 1] + sj_horizontal_extension;
    open_cost = close_block_diagonal[j - 1] +
                sj_gap_opening + sj_gap_extension;
    if (DEBUG_AFFINE)
        printf ("Ext cost: %d, Open cost: %d, Gap extension: %d, gap opening: %d, sj_horizontal_extension: %d\n", 
                ext_cost, open_cost, sj_gap_extension, sj_gap_opening, sj_horizontal_extension);
    if (ext_cost < open_cost)
        extend_horizontal[j] = ext_cost;
    else
        extend_horizontal[j] = open_cost;
    if (DEBUG_AFFINE)
        printf ("The final cost is %d\n", extend_horizontal[j]);
    return;
}

DIRECTION_MATRIX
FILL_EXTEND_HORIZONTAL (int sj_horizontal_extension, int sj_gap_extension, int sj_gap_opening, int j, 
                        int *extend_horizontal, const cost_matrices_2d_p c, 
                        const int *close_block_diagonal, DIRECTION_MATRIX direction_matrix) {
    int ext_cost, open_cost;
    ext_cost = extend_horizontal[j - 1] + sj_horizontal_extension;
    open_cost = close_block_diagonal[j - 1] +
                sj_gap_opening + sj_gap_extension;
    if (DEBUG_AFFINE)
        printf ("Ext cost: %d, Open cost: %d, Gap extension: %d, gap opening: %d, sj_horizontal_extension: %d\n", 
                ext_cost, open_cost, sj_gap_extension, sj_gap_opening, sj_horizontal_extension);
    if (ext_cost < open_cost) {
        LOR_WITH_DIRECTION_MATRIX(BEGIN_HORIZONTAL, direction_matrix);
        extend_horizontal[j] = ext_cost;
    }
    else {
        LOR_WITH_DIRECTION_MATRIX(END_HORIZONTAL, direction_matrix);
        extend_horizontal[j] = open_cost;
    }
    if (DEBUG_AFFINE)
        printf ("The final cost is %d\n", extend_horizontal[j]);
    return (direction_matrix);
}

void
FILL_EXTEND_VERTICAL_NOBT (int si_vertical_extension, int si_gap_extension, int si_gap_opening, int j, 
                           int *extend_vertical, const int *prev_extend_vertical, const cost_matrices_2d_p c, 
                           const int *prev_close_block_diagonal) {
    int ext_cost, open_cost;
    ext_cost = prev_extend_vertical[j] + si_vertical_extension;
    open_cost = prev_close_block_diagonal[j] +
        si_gap_opening + si_gap_extension;
    if (ext_cost < open_cost)
        extend_vertical[j] = ext_cost;
    else
        extend_vertical[j] = open_cost;
    return;
}

DIRECTION_MATRIX
FILL_EXTEND_VERTICAL (int si_vertical_extension, int si_gap_extension, int si_gap_opening, int j, 
                      int *extend_vertical, const int *prev_extend_vertical, const cost_matrices_2d_p c, 
                      const int *prev_close_block_diagonal, 
                      DIRECTION_MATRIX direction_matrix) {
    int ext_cost, open_cost;
    ext_cost = prev_extend_vertical[j] + si_vertical_extension;
    open_cost = prev_close_block_diagonal[j] +
        si_gap_opening + si_gap_extension;
    if (ext_cost < open_cost) {
        LOR_WITH_DIRECTION_MATRIX(BEGIN_VERTICAL, direction_matrix);
        extend_vertical[j] = ext_cost;
    }
    else {
        LOR_WITH_DIRECTION_MATRIX(END_VERTICAL, direction_matrix);
        extend_vertical[j] = open_cost;
    }
    return (direction_matrix);
}

void
FILL_EXTEND_BLOCK_DIAGONAL_NOBT (SEQT si_base, SEQT sj_base, SEQT si_prev_base, 
                                 SEQT sj_prev_base, int gap_open, int j, 
                                 int *extend_block_diagonal, const int *prev_extend_block_diagonal, 
                                 const int *prev_close_block_diagonal) {
    int ext_cost, open_cost;
    int diag, open_diag, flag, flag2;
    flag = ((TMPGAP & si_base) && (TMPGAP & sj_base));
    flag2= (!(TMPGAP & si_prev_base) && (!(TMPGAP & sj_base)));
    diag = flag ? 0 : INT_MAX;
    open_diag = flag ? (flag2 ? 0 : (2 * gap_open)) : INT_MAX;
    ext_cost = prev_extend_block_diagonal[j - 1] + diag;
    open_cost = prev_close_block_diagonal[j - 1] + open_diag;
    if (ext_cost < open_cost)
        extend_block_diagonal[j] = ext_cost;
    else
        extend_block_diagonal[j] = open_cost;
    return;
}

DIRECTION_MATRIX
FILL_EXTEND_BLOCK_DIAGONAL (SEQT si_base, SEQT sj_base, SEQT si_prev_base, SEQT sj_prev_base, 
                            int gap_open, int j, 
                            int *extend_block_diagonal, const int *prev_extend_block_diagonal, 
                            const int *prev_close_block_diagonal, 
                            DIRECTION_MATRIX direction_matrix) {
    int ext_cost, open_cost;
    int diag, open_diag;
    diag = ((TMPGAP & si_base) && (TMPGAP & sj_base))?0:INT_MAX;
    open_diag = (!(TMPGAP & si_prev_base) && (!(TMPGAP & sj_base)) && (TMPGAP & si_base) && (TMPGAP & sj_base))?
        0:(((TMPGAP & si_base) && (TMPGAP & sj_base))?(2 * gap_open):INT_MAX);
    ext_cost = prev_extend_block_diagonal[j - 1] + diag;
    open_cost = prev_close_block_diagonal[j - 1] + diag;
    if (ext_cost < open_cost) {
        LOR_WITH_DIRECTION_MATRIX(BEGIN_BLOCK, direction_matrix);
        extend_block_diagonal[j] = ext_cost;
    }
    else {
        LOR_WITH_DIRECTION_MATRIX(END_BLOCK, direction_matrix);
        extend_block_diagonal[j] = open_cost;
    }
    return (direction_matrix);
}

void
FILL_CLOSE_BLOCK_DIAGONAL_NOBT(SEQT si_base, SEQT sj_base, SEQT si_no_gap, 
                               SEQT sj_no_gap, int si_gap_opening, int sj_gap_opening, int j, 
                               const int *c, int *close_block_diagonal, 
                               const int *prev_close_block_diagonal, const int *prev_extend_vertical, 
                               const int *prev_extend_horizontal, const int *prev_extend_block_diagonal) {
    int diag, extra_gap_opening;
    int algn, from_vertical, from_horizontal, from_diagonal;
    diag = c[sj_no_gap];
    /*
    diag = cm_calc_cost(c->cost, si_no_gap, sj_no_gap, c->lcm);
    */
    extra_gap_opening = (sj_gap_opening < si_gap_opening)?si_gap_opening:sj_gap_opening;
    if (DEBUG_AFFINE) {
        //printf ("Between %d and %d: Diag : %d, Extra gap opening: %d\n", si_no_gap, sj_no_gap, diag, extra_gap_opening);
        //fflush (stdout);
    }
    algn = prev_close_block_diagonal[j - 1] + diag;
    if (si_base == si_no_gap)
        from_vertical = prev_extend_vertical[j - 1] + diag;
    else
        from_vertical = prev_extend_vertical[j - 1] + diag + sj_gap_opening;
    if (sj_base == sj_no_gap)
        from_horizontal = prev_extend_horizontal[j - 1] + diag;
    else
        from_horizontal = prev_extend_horizontal[j - 1] + diag + si_gap_opening;
    from_diagonal = prev_extend_block_diagonal[j - 1] + diag + extra_gap_opening;
    close_block_diagonal[j] = algn;
    if (close_block_diagonal[j] > from_vertical)
        close_block_diagonal[j] = from_vertical;
    if (close_block_diagonal[j] > from_horizontal)
            close_block_diagonal[j] = from_horizontal;
    if (close_block_diagonal[j] > from_diagonal)
            close_block_diagonal[j] = from_diagonal;
    return;
}

DIRECTION_MATRIX
FILL_CLOSE_BLOCK_DIAGONAL(SEQT si_base, SEQT sj_base, SEQT si_no_gap, 
                          SEQT sj_no_gap, int si_gap_opening, int sj_gap_opening, int j, 
                          const int *c, int *close_block_diagonal, 
                          const int *prev_close_block_diagonal, const int *prev_extend_vertical, 
                          const int *prev_extend_horizontal, const int *prev_extend_block_diagonal, 
        DIRECTION_MATRIX direction_matrix) {
    int diag, extra_gap_opening;
    int algn, from_vertical, from_horizontal, from_diagonal;
    DIRECTION_MATRIX mask;
    diag = c[sj_no_gap];
    /*
        cm_calc_cost(c->cost, si_no_gap, sj_no_gap, c->lcm);
        */
    extra_gap_opening =
        (sj_gap_opening < si_gap_opening)?si_gap_opening:sj_gap_opening;
    if (DEBUG_AFFINE) {
        // printf ("Between %d and %d: Diag : %d, Extra gap opening: %d\n", si_no_gap, sj_no_gap, diag, extra_gap_opening);
        // fflush (stdout);
    }
    algn = prev_close_block_diagonal[j - 1] + diag;
    if (si_base == si_no_gap)
        from_vertical = prev_extend_vertical[j - 1] + diag;
    else
        from_vertical = prev_extend_vertical[j - 1] + diag + sj_gap_opening;
    if (sj_base == sj_no_gap)
        from_horizontal = prev_extend_horizontal[j - 1] + diag;
    else
        from_horizontal = prev_extend_horizontal[j - 1] + diag + si_gap_opening;
    from_diagonal = prev_extend_block_diagonal[j - 1] + diag + extra_gap_opening;
    mask = ALIGN_TO_ALIGN;
    close_block_diagonal[j] = algn;
    if (close_block_diagonal[j] >= from_vertical) {
        if (close_block_diagonal[j] > from_vertical) {
            close_block_diagonal[j] = from_vertical;
            mask = ALIGN_TO_VERTICAL;
        }
        else mask = mask | ALIGN_TO_VERTICAL;
    }
    if (close_block_diagonal[j] >= from_horizontal) {
        if (close_block_diagonal[j] > from_horizontal) {
            close_block_diagonal[j] = from_horizontal;
            mask = ALIGN_TO_HORIZONTAL;
        }
        else mask = mask | ALIGN_TO_HORIZONTAL;
    }
    if (close_block_diagonal[j] >= from_diagonal) {
        if (close_block_diagonal[j] > from_diagonal) {
            close_block_diagonal[j] = from_diagonal;
            mask = ALIGN_TO_DIAGONAL;
        }
        else mask = mask | ALIGN_TO_DIAGONAL;
    }
    LOR_WITH_DIRECTION_MATRIX(mask, direction_matrix);
    return (direction_matrix);
}

enum MODE { m_todo, m_vertical, m_horizontal, m_diagonal, m_align } backtrace_mode;


void
backtrace_affine (DIRECTION_MATRIX *direction_matrix, const seq_p si, const seq_p sj, 
                  seq_p median, seq_p medianwg, seq_p resi, seq_p resj, const cost_matrices_2d_p c) {
#define HAS_FLAG(flag) (*direction_matrix & flag)
    enum MODE mode = m_todo;
    int i, j, leni, lenj;
    SEQT ic, jc, prep;
    DIRECTION_MATRIX *initial_direction_matrix;
    i = seq_get_len(si) - 1;
    j = seq_get_len(sj) - 1;
    leni = i;
    lenj = j;
    assert (leni <= lenj);
    ic = seq_get_element(si, i);
    jc = seq_get_element(sj, j);
    initial_direction_matrix = direction_matrix;
    direction_matrix = direction_matrix + (((leni + 1) * (lenj + 1)) - 1);
    while ((i != 0) && (j != 0)) {
        if (DEBUG_AFFINE) {
            printf ("In position %d %d of affine backtrace\n", i, j);
            fflush (stdout);
        }
        assert (initial_direction_matrix < direction_matrix);
        if (mode == m_todo) {
            if (HAS_FLAG(DO_HORIZONTAL)) {
                mode = m_horizontal;
            } else if (HAS_FLAG(DO_ALIGN)) {
                mode = m_align;
            } else if (HAS_FLAG(DO_VERTICAL)) {
                mode = m_vertical;
            } else {
                assert (HAS_FLAG(DO_DIAGONAL));
                mode = m_diagonal;
            }
        } else if (mode == m_vertical) {
            if (HAS_FLAG(END_VERTICAL)) {
                mode = m_todo;
            }
            if (!(ic & TMPGAP)) {
                seq_prepend (median, (ic | TMPGAP));
                seq_prepend (medianwg, (ic | TMPGAP));
            } else {
                seq_prepend (medianwg, TMPGAP);
            }
            seq_prepend(resi, ic);
            seq_prepend(resj, TMPGAP);
            i--;
            direction_matrix -= (lenj + 1);
            ic = seq_get_element(si, i);
        } else if (mode == m_horizontal) {
            if (HAS_FLAG(END_HORIZONTAL)) {
                mode = m_todo;
            }
            if (!(jc & TMPGAP)) {
                seq_prepend (median, (jc | TMPGAP));
                seq_prepend (medianwg, (jc | TMPGAP));
            } else {
                seq_prepend (medianwg, TMPGAP);
            }
            seq_prepend (resi, TMPGAP);
            seq_prepend (resj, jc);
            j--;
            direction_matrix -= 1;
            jc = seq_get_element(sj, j);
        } else if (mode == m_diagonal) {
            if (HAS_FLAG(END_BLOCK)) {
                mode = m_todo;
            }
            seq_prepend(resi, ic);
            seq_prepend(resj, jc);
            seq_prepend(medianwg, TMPGAP);
            i--;
            j--;
            direction_matrix -= (lenj + 2);
            jc = seq_get_element(sj, j);
            ic = seq_get_element(si, i);
        } else {
            assert (mode == m_align);
            if (HAS_FLAG(ALIGN_TO_HORIZONTAL)) {
                mode = m_horizontal;
            } else if (HAS_FLAG(ALIGN_TO_DIAGONAL)) {
                mode = m_diagonal;
            } else if (HAS_FLAG(ALIGN_TO_VERTICAL)) {
                mode = m_vertical;
            }
            prep = cm_get_median(c, (ic & (NTMPGAP)), (jc & (NTMPGAP)));
            seq_prepend(median, prep);
            seq_prepend(medianwg, prep);
            seq_prepend(resi, ic);
            seq_prepend(resj, jc);
            i--;
            j--;
            direction_matrix -= (lenj + 2);
            jc = seq_get_element(sj, j);
            ic = seq_get_element(si, i);
        }
    }
    while (i != 0) {
        assert (initial_direction_matrix < direction_matrix);
        if (!(ic & TMPGAP)) {
            seq_prepend (median, (ic | TMPGAP));
            seq_prepend (medianwg, (ic | TMPGAP));
        } else {
            seq_prepend (medianwg, TMPGAP);
        }
        seq_prepend(resi, ic);
        seq_prepend(resj, TMPGAP);
        direction_matrix -= (lenj + 1);
        i--;
        ic = seq_get_element(si, i);
    }
    while (j != 0) {
        assert (initial_direction_matrix < direction_matrix);
        if (!(jc & TMPGAP)) {
            seq_prepend (median, (jc | TMPGAP));
            seq_prepend (medianwg, (jc | TMPGAP));
        } else {
            seq_prepend (medianwg, TMPGAP);
        }
        seq_prepend (resi, TMPGAP);
        seq_prepend (resj, jc);
        j--;
        direction_matrix -= 1;
        jc = seq_get_element(sj, j);
    }
    seq_prepend(resi, TMPGAP);
    seq_prepend(resj, TMPGAP);
    seq_prepend(medianwg, TMPGAP);
    if (TMPGAP != seq_get_element(median, 0)) {
        seq_prepend(median, TMPGAP);
    }
#undef HAS_FLAG
    return;

}

void
print_array (char *title, int *arr, int max) {
    int i;
    printf ("%s", title);
    for (i = 0; i <= max; i++) {
        printf ("%d ", arr[i]);
    }
    printf ("\n");
    fflush (stdout);
    return;
}

void
print_dirMtx (char *title, DIRECTION_MATRIX *arr, int max) {
    int i;
    printf ("%s", title);
    for (i = 0; i <= max; i++) {
        printf ("%d ", arr[i]);
    }
    printf ("\n");
    fflush (stdout);
    return;
}

// TODO: what is this?
void
initialize_matrices_affine_nobt (int go, const seq_p si, const seq_p sj, 
                                 const cost_matrices_2d_p c, 
                                 int *close_block_diagonal, int *extend_block_diagonal, 
                                 int *extend_vertical, int *extend_horizontal, 
                                 const int *precalcMtx) {
    int leni, lenj, i = 1, j = 1, r;
    int *prev_extend_vertical;
    const int *gap_row;
    SEQT jc, jp, ic, ip;
    leni = seq_get_len(si) - 1;
    lenj = seq_get_len(sj) - 1;
    close_block_diagonal[0] = 0;
    extend_block_diagonal[0] = 0;
    extend_horizontal[0] = go;
    extend_vertical[0] = go;
    gap_row = cm_get_precal_row(precalcMtx, 0, lenj);
    if (DEBUG_AFFINE) {
        printf("initialize_matrices_affine_nobt\n");
        printf ("\n\nThe gap opening parameter is %d\n", go);
        printf ("\nPre-initialized values:\n");
        print_array  ("CB :", close_block_diagonal, lenj);
        print_array  ("EB :", extend_block_diagonal, lenj);
        print_array  ("EV :", extend_vertical, lenj);
        print_array  ("EH :", extend_horizontal, lenj);
    }
    for (; j <= lenj; j++) {
        jc = seq_get_element(sj, j);
        jp = seq_get_element(sj, j - 1);
        r = extend_horizontal[j - 1] + gap_row[j];
        extend_horizontal[j] = r;
        close_block_diagonal[j] = r;
        extend_block_diagonal[j] = INT_MAX;
        extend_vertical[j] = INT_MAX;
    }
    if (DEBUG_AFFINE) {
        printf("initialize_matrices_affine_nobt\n");
        printf ("\nInitialized values:\n");
        print_array  ("CB :", close_block_diagonal, lenj);
        print_array  ("EB :", extend_block_diagonal, lenj);
        print_array  ("EV :", extend_vertical, lenj);
        print_array  ("EH :", extend_horizontal, lenj);
        printf ("Finished initialization\n\n");
    }
    /* for (; i <= leni; i++) { */
        prev_extend_vertical   = extend_vertical;
        extend_vertical       += (1 + lenj);
        close_block_diagonal  += (1 + lenj);
        extend_block_diagonal += (1 + lenj);
        extend_horizontal     += (1 + lenj);
        ic = seq_get_element(si, i);
        ip = seq_get_element(si, i - 1);
        r  = prev_extend_vertical[0] + (HAS_GAP_EXTENSION(ic, c));
        extend_horizontal[0]     = INT_MAX;
        close_block_diagonal[0]  = r;
        extend_block_diagonal[0] = INT_MAX;
        extend_vertical[0]       = r;
    /* } */
    return;
}


void
initialize_matrices_affine (int go, const seq_p si, const seq_p sj, 
                            const cost_matrices_2d_p c, 
                            int *close_block_diagonal, int *extend_block_diagonal, 
                            int *extend_vertical, int *extend_horizontal, int *final_cost_matrix, 
                            DIRECTION_MATRIX *direction_matrix, const int *precalcMtx) {
    int leni, lenj, i = 1, j = 1, r;
    int *prev_extend_vertical;
    const int *gap_row;
    SEQT jc, jp, ic, ip;
    leni = seq_get_len(si) - 1; //TODO: is this for deleting opening gap?
    lenj = seq_get_len(sj) - 1; //TODO: is this for deleting opening gap?
    final_cost_matrix[0]     = 0;
    close_block_diagonal[0]  = 0;
    extend_block_diagonal[0] = 0;
    extend_horizontal[0]     = go;
    extend_vertical[0]       = go;
    direction_matrix[0]      = 0xFFFF;
    gap_row = cm_get_precal_row(precalcMtx, 0, lenj);
    if (DEBUG_AFFINE) {
        printf("initialize_matrices_affine\n");
        printf ("\n\nThe gap opening parameter is %d\n", go);
        printf ("\nPre-initialized values:\n");
        print_array ("CB :", close_block_diagonal,  lenj);
        print_array ("EB :", extend_block_diagonal, lenj);
        print_array ("EV :", extend_vertical,       lenj);
        print_array ("EH :", extend_horizontal,     lenj);
        print_array ("FC :", final_cost_matrix,     lenj);
    }
    for (; j <= lenj; j++) {
        jc = seq_get_element(sj, j);
        jp = seq_get_element(sj, j - 1);
        r  = extend_horizontal[j - 1] + gap_row[j];

        extend_horizontal[j]     = r;
        close_block_diagonal[j]  = r;
        final_cost_matrix[j]     = r;
        extend_block_diagonal[j] = INT_MAX;
        extend_vertical[j]       = INT_MAX;
        direction_matrix[j]      = DO_HORIZONTAL | END_HORIZONTAL;
    }
    if (DEBUG_AFFINE) {
        printf("initialize_matrices_affine_nobt\n");
        printf ("\nInitialized values:\n");
        print_array  ("CB :", close_block_diagonal, lenj);
        print_array  ("EB :", extend_block_diagonal, lenj);
        print_array  ("EV :", extend_vertical, lenj);
        print_array  ("EH :", extend_horizontal, lenj);
        print_array  ("FC :", final_cost_matrix, lenj);
        printf ("Finished initializing.\n");
    }
    /* for (; i <= leni; i++) { */
        prev_extend_vertical   = extend_vertical;
        extend_vertical       += (1 + lenj);
        close_block_diagonal  += (1 + lenj);
        final_cost_matrix     += (1 + lenj);
        extend_block_diagonal += (1 + lenj);
        extend_horizontal     += (1 + lenj);
        direction_matrix      += (1 + lenj);

        ic = seq_get_element(si, i);
        ip = seq_get_element(si, i - 1);
        r  = prev_extend_vertical[0] + (HAS_GAP_EXTENSION(ic, c));

        extend_horizontal[0]     = INT_MAX;
        close_block_diagonal[0]  = r;
        final_cost_matrix[0]     = r;
        extend_block_diagonal[0] = INT_MAX;
        extend_vertical[0]       = r;
        direction_matrix[0]      = DO_VERTICAL | END_VERTICAL;
    /* } */
    return;
}

DIRECTION_MATRIX
ASSIGN_MINIMUM (int *final_cost_matrix, int extend_horizontal, 
                int extend_vertical, int extend_block_diagonal, 
                int close_block_diagonal, DIRECTION_MATRIX direction_matrix) {
    int mask;
    mask = DO_HORIZONTAL;
    *final_cost_matrix = extend_horizontal;
    if (*final_cost_matrix >= extend_vertical) {
        if (*final_cost_matrix > extend_vertical) {
            *final_cost_matrix = extend_vertical;
            mask = DO_VERTICAL;
        }
        else mask = mask | DO_VERTICAL;
    }
    if (*final_cost_matrix >= extend_block_diagonal) {
        if (*final_cost_matrix > extend_block_diagonal) {
            *final_cost_matrix = extend_block_diagonal;
            mask = DO_DIAGONAL;
        }
        else mask = mask | DO_DIAGONAL;
    }
    if (*final_cost_matrix >= close_block_diagonal) {
        if (*final_cost_matrix > close_block_diagonal) {
            *final_cost_matrix = close_block_diagonal;
            mask = DO_ALIGN;
        }
        else mask = mask | DO_ALIGN;
    }
    LOR_WITH_DIRECTION_MATRIX(mask, direction_matrix);
    return (direction_matrix);
}

int
algn_fill_plane_3_affine_nobt (const seq_p si, const seq_p sj, int leni, int lenj, 
                            const cost_matrices_2d_p c, int *extend_horizontal, int *extend_vertical, 
                            int *close_block_diagonal, int *extend_block_diagonal, const int *precalcMtx, 
                            int *gap_open_prec, int *sj_horizontal_extension) {
    int start_pos = 1, end_pos, start_v = 40, i=1, j, res;
    int *prev_extend_horizontal, *prev_extend_vertical, *prev_close_block_diagonal, 
        *prev_extend_block_diagonal;
    int *init_extend_horizontal, *init_extend_vertical, *init_close_block_diagonal, 
        *init_extend_block_diagonal;
    const int *si_no_gap_vector;
    int si_gap_opening, si_gap_extension, sj_gap_opening, sj_gap_extension;
    int gap, gap_open;
    const int *gap_row;
    int si_vertical_extension;
    gap = c->gap;
    gap_open = c->gap_open;
    assert (lenj >= leni);
    init_extend_horizontal = extend_horizontal;
    init_extend_vertical = extend_vertical;
    init_extend_block_diagonal = extend_block_diagonal;
    init_close_block_diagonal = close_block_diagonal;
    gap_row = cm_get_precal_row(precalcMtx, 0, lenj);
    end_pos = (lenj - leni) + 8;
    if (DEBUG_AFFINE) {
        printf("\n--algn fill plane 3 affine nobt\n");
        printf("Before initializing:\n");
        print_array  ("CB :", close_block_diagonal, lenj);
        print_array  ("EB :", extend_block_diagonal, lenj);
        print_array  ("EV :", extend_vertical, lenj);
        print_array  ("EH :", extend_horizontal, lenj);
    }
    if (end_pos < 40) end_pos = 40;
    if (end_pos > lenj) end_pos = lenj;
    SEQT jc, jp, ic, ip, si_no_gap, sj_no_gap;
    SEQT *begini, *beginj;
    begini = si->begin;
    beginj = sj->begin;
    ic = begini[0];
    for (j = 1; j <= lenj; j++) {
        gap_open_prec[j] = HAS_GAP_OPENING(beginj[j - 1], beginj[j], gap, gap_open);
        if ((beginj[j - 1] & gap) && (!(beginj[j] & gap)))
            sj_horizontal_extension[j] = gap_open_prec[j] + gap_row[j];
        else sj_horizontal_extension[j] = gap_row[j];
    }
    sj_horizontal_extension[1] = gap_row[1];
    int r;
    for (;i <= leni; i++) {
        prev_extend_horizontal = init_extend_horizontal +
            (((i - 1) % 2) * (lenj + 1));
        prev_extend_vertical = init_extend_vertical +
            ((lenj + 1) * ((i - 1) % 2));
        prev_extend_block_diagonal =
            init_extend_block_diagonal + ((lenj + 1) * ((i - 1) % 2));
        prev_close_block_diagonal = init_close_block_diagonal +
            ((lenj + 1) * ((i - 1) % 2));
        extend_horizontal = init_extend_horizontal + ((i % 2) * (lenj + 1));
        extend_vertical = init_extend_vertical + ((lenj + 1) * (i % 2));
        extend_block_diagonal =
            init_extend_block_diagonal + ((lenj + 1) * (i % 2));
        close_block_diagonal = init_close_block_diagonal + ((lenj + 1) * (i % 2));
        if (i > start_v) start_pos++;
        extend_horizontal[start_pos - 1] = INT_MAX;
        ip = ic;
        ic = begini[i];
        si_gap_extension = HAS_GAP_EXTENSION(ic, c);
        si_gap_opening = HAS_GAP_OPENING (ip, ic, gap, gap_open);
        si_no_gap = (NTMPGAP) & ic;
        if ((i > 1) && ((ip & gap) && (!(ic & gap))))
            si_vertical_extension = si_gap_opening + si_gap_extension;
        else si_vertical_extension = si_gap_extension;
        r = prev_extend_vertical[start_pos - 1] + si_vertical_extension;
        extend_horizontal[start_pos - 1] = INT_MAX;
        close_block_diagonal[start_pos - 1] = r;
        extend_block_diagonal[start_pos - 1] = INT_MAX;
        extend_vertical[start_pos - 1] = r;
        jc = beginj[start_pos - 1];
        close_block_diagonal[start_pos - 1] = INT_MAX;
        si_no_gap_vector = c->cost + (si_no_gap << c->lcm);
        for (j=start_pos; j <= end_pos; j++) {
            jp = jc;
            jc = beginj[j];
            sj_no_gap = (NTMPGAP) & jc;
            sj_gap_extension = gap_row[j];
            sj_gap_opening = gap_open_prec[j];
            FILL_EXTEND_HORIZONTAL_NOBT(sj_horizontal_extension[j], sj_gap_extension, 
                                        sj_gap_opening, j, 
                                        extend_horizontal, c, close_block_diagonal);
            FILL_EXTEND_VERTICAL_NOBT(si_vertical_extension, si_gap_extension, si_gap_opening, j, 
                                      extend_vertical, prev_extend_vertical, c, 
                                      prev_close_block_diagonal);
            FILL_EXTEND_BLOCK_DIAGONAL_NOBT(ic, jc, ip, jp, gap_open, j, extend_block_diagonal, 
                                            prev_extend_block_diagonal, 
                                            prev_close_block_diagonal);
            FILL_CLOSE_BLOCK_DIAGONAL_NOBT(ic, jc, si_no_gap, sj_no_gap, 
                                           si_gap_opening, sj_gap_opening, j, si_no_gap_vector, close_block_diagonal, 
                                           prev_close_block_diagonal, 
                                           prev_extend_vertical, prev_extend_horizontal, 
                                           prev_extend_block_diagonal);
        }
        if (end_pos < lenj) {
            end_pos++;
            extend_vertical[end_pos] = INT_MAX;
            close_block_diagonal[end_pos] = INT_MAX;
            extend_horizontal[end_pos] = INT_MAX;
            extend_block_diagonal[end_pos] = INT_MAX;
        }
        if (DEBUG_AFFINE) {
            printf("algn fill plane 3 affine nobt\n");
            printf("After initializing:\n");
            print_array  ("CB :", close_block_diagonal, lenj);
            print_array  ("EB :", extend_block_diagonal, lenj);
            print_array  ("EV :", extend_vertical, lenj);
            print_array  ("EH :", extend_horizontal, lenj);
        }
    }
    res = extend_horizontal[lenj];
    if (res > extend_vertical[lenj]) res = extend_vertical[lenj];
    if (res > extend_block_diagonal[lenj]) res = extend_block_diagonal[lenj];
    if (res > close_block_diagonal[lenj]) res = close_block_diagonal[lenj];
    return res;
}


int
algn_fill_plane_3_affine (const seq_p si, const seq_p sj, int leni, int lenj, 
                       int *final_cost_matrix, DIRECTION_MATRIX *direction_matrix, 
                       const cost_matrices_2d_p c, int *extend_horizontal, int *extend_vertical, 
                       int *close_block_diagonal, int *extend_block_diagonal, const int *precalcMtx, 
                       int *gap_open_prec, int *sj_horizontal_extension) {
    int start_pos = 1, end_pos, start_v = 40, i = 1, j, res;
    int *prev_extend_horizontal, *prev_extend_vertical, *prev_close_block_diagonal, 
        *prev_extend_block_diagonal;
    int *init_extend_horizontal, *init_extend_vertical, *init_close_block_diagonal, 
        *init_extend_block_diagonal;
    const int *si_no_gap_vector;
    int si_gap_opening, si_gap_extension, sj_gap_opening, sj_gap_extension;
    int gap, gap_open;
    const int *gap_row;
    int si_vertical_extension;
    DIRECTION_MATRIX tmp_direction_matrix;
    gap = c->gap;
    gap_open = c->gap_open;
    assert (lenj >= leni);
    init_extend_horizontal = extend_horizontal;
    init_extend_vertical = extend_vertical;
    init_extend_block_diagonal = extend_block_diagonal;
    init_close_block_diagonal = close_block_diagonal;
    gap_row = cm_get_precal_row(precalcMtx, 0, lenj);
    end_pos = (lenj - leni) + 8;
    if (DEBUG_AFFINE) {
        printf("\n--algn fill plane 3 affine\n");
        printf("Before initializing:\n");
        print_array  ("CB :", close_block_diagonal, lenj);
        print_array  ("EB :", extend_block_diagonal, lenj);
        print_array  ("EV :", extend_vertical, lenj);
        print_array  ("EH :", extend_horizontal, lenj);
        print_array  ("FC :", final_cost_matrix, lenj);
        print_dirMtx ("DM :", direction_matrix, lenj);
    }
    if (end_pos < 40) end_pos = 40;
    if (end_pos > lenj) end_pos = lenj;
    //end_pos = lenj;
    SEQT jc, jp, ic, ip, si_no_gap, sj_no_gap;
    SEQT *begini, *beginj;
    begini = si->begin;
    beginj = sj->begin;
    ic = begini[0];
    for (j = 1; j <= lenj; j++) {
        gap_open_prec[j] = HAS_GAP_OPENING(beginj[j - 1], beginj[j], gap, gap_open);
        if ((beginj[j - 1] & gap) && (!(beginj[j] & gap)))
            sj_horizontal_extension[j] = gap_open_prec[j] + gap_row[j];
        else sj_horizontal_extension[j] = gap_row[j];
    }
    sj_horizontal_extension[1] = gap_row[1];
    int r;
    for (;i <= leni; i++) {
        prev_extend_horizontal = init_extend_horizontal +
            (((i - 1) % 2) * (lenj + 1));
        prev_extend_vertical = init_extend_vertical +
            ((lenj + 1) * ((i - 1) % 2));
        prev_extend_block_diagonal =
            init_extend_block_diagonal + ((lenj + 1) * ((i - 1) % 2));
        prev_close_block_diagonal = init_close_block_diagonal +
            ((lenj + 1) * ((i - 1) % 2));
        extend_horizontal = init_extend_horizontal + ((i % 2) * (lenj + 1));
        extend_vertical = init_extend_vertical + ((lenj + 1) * (i % 2));
        extend_block_diagonal =
            init_extend_block_diagonal + ((lenj + 1) * (i % 2));
        close_block_diagonal = init_close_block_diagonal + ((lenj + 1) * (i % 2));
        direction_matrix = direction_matrix + (lenj + 1);
        if (i > start_v) start_pos++;
        direction_matrix[start_pos - 1] = DO_VERTICAL | END_VERTICAL;
        extend_horizontal[start_pos - 1] = INT_MAX;
        ip = ic;
        ic = begini[i];
        si_gap_extension = HAS_GAP_EXTENSION(ic, c);
        si_gap_opening = HAS_GAP_OPENING (ip, ic, gap, gap_open);
        si_no_gap = (NTMPGAP) & ic;
        if ((i > 1) && ((ip & gap) && (!(ic & gap))))
            si_vertical_extension = si_gap_opening + si_gap_extension;
        else si_vertical_extension = si_gap_extension;
        r = prev_extend_vertical[start_pos - 1] + si_vertical_extension;
        extend_horizontal[start_pos - 1] = INT_MAX;
        close_block_diagonal[start_pos - 1] = r;
        final_cost_matrix[start_pos - 1] = r;
        extend_block_diagonal[start_pos - 1] = INT_MAX;
        extend_vertical[start_pos - 1] = r;
        direction_matrix[start_pos - 1] = DO_VERTICAL | END_VERTICAL;
        jc = beginj[start_pos - 1];
        close_block_diagonal[start_pos - 1] = INT_MAX;
        si_no_gap_vector = c->cost + (si_no_gap << c->lcm);
        for (j=start_pos; j <= end_pos; j++) {
            jp = jc;
            jc = beginj[j];
            tmp_direction_matrix = 0;
            sj_no_gap = (NTMPGAP) & jc;
            sj_gap_extension = gap_row[j];
            sj_gap_opening = gap_open_prec[j];
            tmp_direction_matrix =
                FILL_EXTEND_HORIZONTAL(sj_horizontal_extension[j], sj_gap_extension, 
                                       sj_gap_opening, j, 
                                       extend_horizontal, c, close_block_diagonal, tmp_direction_matrix);
            tmp_direction_matrix =
                FILL_EXTEND_VERTICAL(si_vertical_extension, si_gap_extension, si_gap_opening, j, 
                                     extend_vertical, prev_extend_vertical, c, 
                                     prev_close_block_diagonal, tmp_direction_matrix);
            tmp_direction_matrix =
                FILL_EXTEND_BLOCK_DIAGONAL(ic, jc, ip, jp, gap_open, j, extend_block_diagonal, 
                                           prev_extend_block_diagonal, 
                                           prev_close_block_diagonal, tmp_direction_matrix);
            tmp_direction_matrix =
                FILL_CLOSE_BLOCK_DIAGONAL(ic, jc, si_no_gap, sj_no_gap, 
                                          si_gap_opening, sj_gap_opening, j, si_no_gap_vector, close_block_diagonal, 
                                          prev_close_block_diagonal, 
                                          prev_extend_vertical, prev_extend_horizontal, 
                                          prev_extend_block_diagonal, 
                                          tmp_direction_matrix);
            tmp_direction_matrix =
                ASSIGN_MINIMUM (final_cost_matrix + j, extend_horizontal[j], 
                                extend_vertical[j], extend_block_diagonal[j], 
                                close_block_diagonal[j], tmp_direction_matrix);
            direction_matrix[j] = tmp_direction_matrix;
        }
        if (end_pos < lenj) {
            end_pos++;
            direction_matrix[end_pos] = DO_HORIZONTAL | END_HORIZONTAL;
            extend_vertical[end_pos] = INT_MAX;
            close_block_diagonal[end_pos] = INT_MAX;
            extend_horizontal[end_pos] = INT_MAX;
            extend_horizontal[end_pos] = INT_MAX;
            extend_block_diagonal[end_pos] = INT_MAX;
        }
        if (DEBUG_AFFINE) {
            printf("\n--algn fill plane 3 affine\n");
            printf("Inside loop:\n");
            print_array  ("CB :", close_block_diagonal, lenj);
            print_array  ("EB :", extend_block_diagonal, lenj);
            print_array  ("EV :", extend_vertical, lenj);
            print_array  ("EH :", extend_horizontal, lenj);
            print_array  ("FC :", final_cost_matrix, lenj);
            print_dirMtx ("DM :", direction_matrix, lenj);
        }
    }
    res = final_cost_matrix[lenj];
    return res;
}

/*
value
algn_CAML_align_affine_3 (value si, value sj, value cm, value am, value resi, 
        value resj, value median, value medianwg) {
    CAMLparam4(si, sj, cm, am);
    CAMLxparam4(resi, resj, median, medianwg);
    seq_p csi, csj;
    seq_p cresj, cresi, cmedian, cmedianwg;
    cost_matrices_2d_p ccm;
    nw_matrices_p cam;
    int leni, lenj;
    int *matrix;
    int *close_block_diagonal;
    int *extend_block_diagonal;
    int *extend_vertical;
    int *extend_horizontal;
    int *final_cost_matrix;
    int *precalcMtx;
    int *gap_open_prec;
    int *s_horizontal_gap_extension;
    int res, largest;
    DIRECTION_MATRIX *direction_matrix;
    Seq_custom_val(csi, si);
    Seq_custom_val(csj, sj);
    ccm = Cost_matrix_struct(cm);
    cam = Matrices_struct(am);
    Seq_custom_val(cresi, resi);
    Seq_custom_val(cresj, resj);
    Seq_custom_val(cmedian, median);
    Seq_custom_val(cmedianwg, medianwg);
    leni = seq_get_len(csi);
    lenj = seq_get_len(csj);
    if (leni > lenj)
        largest = leni;
    else largest = lenj;
    mat_setup_size (cam, largest, largest, 0, 0, cm_get_lcm(ccm));
    matrix = mat_get_2d_nwMtx(cam);
    precalcMtx = mat_get_2d_prec(cam);
    close_block_diagonal = (int *) matrix;
    extend_block_diagonal = (int *) (matrix + (2 * largest));
    extend_vertical = (int *) (matrix + (4 * largest));
    extend_horizontal = (int *) (matrix + (6 * largest));
    final_cost_matrix = (int *) (matrix + (8 * largest));
    gap_open_prec = (int *) (matrix + (10 * largest));
    s_horizontal_gap_extension = (int *) (matrix + (11 * largest));
    direction_matrix =  mat_get_2d_direct(cam);
    if (leni <= lenj) {
        cm_precalc_4algn(ccm, cam, csj);
        initialize_matrices_affine(ccm->gap_open, csi, csj, ccm, close_block_diagonal, 
                extend_block_diagonal, extend_vertical, extend_horizontal, 
                final_cost_matrix, direction_matrix, precalcMtx);
        res = algn_fill_plane_3_affine (csi, csj, leni - 1, lenj - 1, final_cost_matrix, 
            direction_matrix, ccm, extend_horizontal, extend_vertical, 
            close_block_diagonal, extend_block_diagonal, precalcMtx, gap_open_prec, 
            s_horizontal_gap_extension);
        backtrace_affine(direction_matrix, csi, csj, cmedian, cmedianwg, \
                cresi, cresj, ccm);
    } else {
        cm_precalc_4algn(ccm, cam, csi);
        initialize_matrices_affine(ccm->gap_open, csj, csi, ccm, close_block_diagonal, 
                extend_block_diagonal, extend_vertical, extend_horizontal, 
                final_cost_matrix, direction_matrix, precalcMtx);
        res = algn_fill_plane_3_affine (csj, csi, lenj - 1, leni - 1, final_cost_matrix, 
            direction_matrix, ccm, extend_horizontal, extend_vertical, 
            close_block_diagonal, extend_block_diagonal, precalcMtx, gap_open_prec, 
            s_horizontal_gap_extension);
        backtrace_affine(direction_matrix, csj, csi, cmedian, cmedianwg, \
                cresj, cresi, ccm);
    }
    CAMLreturn(Val_int(res));
}

value
algn_CAML_align_affine_3_bc (value *argv, int argn) {
    return (algn_CAML_align_affine_3 (argv[0], argv[1], argv[2], argv[3], argv[4], \
                argv[5], argv[6], argv[7]));
}

value
algn_CAML_cost_affine_3 (value si, value sj, value cm, value am) {
    CAMLparam4(si, sj, cm, am);
    seq_p csi, csj;
    cost_matrices_2d_p ccm;
    nw_matrices_p cam;
    int leni, lenj;
    int *matrix;
    int *close_block_diagonal;
    int *extend_block_diagonal;
    int *extend_vertical;
    int *extend_horizontal;
    int *precalcMtx;
    int *gap_open_prec;
    int *s_horizontal_gap_extension;
    int res, largest;
    Seq_custom_val(csi, si);
    Seq_custom_val(csj, sj);
    ccm = Cost_matrix_struct(cm);
    cam = Matrices_struct(am);
    leni = seq_get_len(csi);
    lenj = seq_get_len(csj);
    if (leni > lenj)
        largest = leni;
    else largest = lenj;
    mat_setup_size (cam, largest, largest, 0, 0, cm_get_lcm(ccm));
    matrix = mat_get_2d_nwMtx(cam);
    close_block_diagonal = (int *) matrix;
    extend_block_diagonal = (int *) (matrix + (2 * largest));
    extend_vertical = (int *) (matrix + (4 * largest));
    extend_horizontal = (int *) (matrix + (6 * largest));
    gap_open_prec = (int *) (matrix + (10 * largest));
    s_horizontal_gap_extension = (int *) (matrix + (11 * largest));
    precalcMtx = mat_get_2d_prec(cam);
    if (leni <= lenj) {
        cm_precalc_4algn(ccm, cam, csj);
        initialize_matrices_affine_nobt(ccm->gap_open, csi, csj, ccm, close_block_diagonal, 
                extend_block_diagonal, extend_vertical, extend_horizontal, 
                precalcMtx);
        res = algn_fill_plane_3_affine_nobt (csi, csj, leni - 1, lenj - 1, 
            ccm, extend_horizontal, extend_vertical, 
            close_block_diagonal, extend_block_diagonal, precalcMtx, gap_open_prec, 
            s_horizontal_gap_extension);
    } else {
        cm_precalc_4algn(ccm, cam, csi);
        initialize_matrices_affine_nobt(ccm->gap_open, csj, csi, ccm, close_block_diagonal, 
                extend_block_diagonal, extend_vertical, extend_horizontal, precalcMtx);
        res = algn_fill_plane_3_affine_nobt (csj, csi, lenj - 1, leni - 1, 
            ccm, extend_horizontal, extend_vertical, 
            close_block_diagonal, extend_block_diagonal, precalcMtx, gap_open_prec, 
            s_horizontal_gap_extension);
    }
    CAMLreturn(Val_int(res));
}
*/

static inline int
algn_fill_plane_2_affine (const seq_p seq1, int *precalcMtx, int seq1_len, int seq2_len, int *curRow, 
                       DIRECTION_MATRIX *dirMtx, const cost_matrices_2d_p c, 
                       int width, int height, int dwidth_height, 
                       int *dncurRow, int *htcurRow) {
    int *next_row, *next_prevRow, *next_dncurRow, *next_pdncurRow;
    int *a, *b, *d, *e, open_gap;
    int const *gap_row;
    int start_row, final_row, start_column, length;
    DIRECTION_MATRIX *to_go_dirMtx;
    open_gap = cm_get_gap_opening_parameter (c);
    width = width + dwidth_height;
    if (width > seq2_len) width = seq2_len;
    height = height + dwidth_height;
    if (height > seq1_len) height = seq1_len;
    a = curRow;
    b = curRow + seq2_len;
    d = dncurRow;
    e = dncurRow + seq2_len;
    gap_row = cm_get_precal_row (precalcMtx, 0, seq2_len); /* We want the horizontal row */
    /* We have to consider three cases in this new alignment procedure (much
     * cleaner than the previous):
     *
     * Case 1:
     * If seq1 is much longer than seq2, then there is no point on using the
     * barriers, we rather fill the full matrix in one shot */
    if (((float) seq1_len) >= (((float) ((float) 3 / (float) 2) * (float) seq2_len)))
        return (algn_fill_plane_affine (seq1, precalcMtx, seq1_len, seq2_len, curRow, dirMtx, c, d, 
                htcurRow, open_gap));
    /* Case 2:
     * There are no full rows to be filled, therefore we have to break the
     * procedure in three different subsets */
    else if ((2 * height) < seq1_len) {
        algn_fill_first_row_affine (a, dirMtx, width, gap_row, d, htcurRow, open_gap);
        b[0] = a[0];
        a[0] = 0;
        start_row = 1;
        final_row = height;
        start_column = 0;
        length = width + 1;
        to_go_dirMtx = dirMtx + (start_row * seq2_len);
        /* Now we fill that space */
        next_row = algn_fill_extending_right_affine (seq1, precalcMtx, seq1_len, seq2_len, b, a, 
                                                  to_go_dirMtx, c, start_row, final_row, 
                                                  length, e, d, htcurRow, open_gap);
        next_prevRow = choose_other (next_row, a, b);
        algn_choose_affine_other (next_row, curRow, &next_dncurRow, &next_pdncurRow, d, e);
        /* Next group */
        start_row = final_row;
        final_row = seq1_len - (height - 1);
        start_column = 1;
        length = width + height;
        to_go_dirMtx = dirMtx + (start_row * seq2_len);
        next_row =
            algn_fill_extending_left_right_affine (seq1, precalcMtx, seq1_len, 
                                                seq2_len, next_row, next_prevRow, to_go_dirMtx, c, start_row, 
                                                final_row, start_column, length, next_dncurRow, next_pdncurRow, 
                                                htcurRow, open_gap);
        next_prevRow = choose_other (next_row, a, b);
        algn_choose_affine_other (next_row, curRow, &next_dncurRow, &next_pdncurRow, d, e);
        /* The final group */
        start_row = final_row;
        final_row = seq1_len;
        length = length - 2;
        start_column = seq2_len - length;
        to_go_dirMtx = dirMtx + (start_row * seq2_len);
        next_row = algn_fill_extending_left_affine (seq1, precalcMtx, seq1_len, seq2_len, 
                                                 next_row, next_prevRow, to_go_dirMtx, c, start_row, final_row, 
                                                 start_column, length, next_dncurRow, next_pdncurRow, 
                                                 htcurRow, open_gap);
        next_prevRow = choose_other (next_row, a, b);
        algn_choose_affine_other (next_row, curRow, &next_dncurRow, &next_pdncurRow, d, e);
    }
    /* Case 3: (final case)
     * There is a block in the middle of with full rows that have to be filled
     * */
    else {
        /* We will simplify this case even further, if the size of the leftover
         * is too small, don't use the barriers at all, just fill it up all */
        if (8 >= (seq1_len - height))
            return (algn_fill_plane_affine (seq1, precalcMtx, seq1_len, seq2_len, curRow, dirMtx, c, 
                                         d, htcurRow, open_gap));
        else {
            algn_fill_first_row_affine (curRow, dirMtx, width, gap_row, dncurRow, htcurRow, open_gap);
            b[0] = curRow[0];
            curRow[0] = 0;
            start_row = 1;
            final_row = (seq2_len - width) + 1;
            start_column = 0;
            length = width + 1;
            to_go_dirMtx = dirMtx + (seq2_len * start_row);
            next_row = algn_fill_extending_right_affine (seq1, precalcMtx, seq1_len, seq2_len, 
                                                      b, a, to_go_dirMtx, c, start_row, final_row, 
                                                      length, e, d, htcurRow, open_gap);
            next_prevRow = choose_other (next_row, a, b);
            algn_choose_affine_other (next_row, curRow, &next_dncurRow, &next_pdncurRow, d, e);
            start_row = final_row;
            final_row = seq1_len - (seq2_len - width) + 1;
            length = seq2_len;
            to_go_dirMtx = dirMtx + (seq2_len * start_row);
            next_row = algn_fill_no_extending_affine (seq1, precalcMtx, seq1_len, seq2_len, 
                                                   next_row, next_prevRow, to_go_dirMtx, c, start_row, 
                                                   final_row, next_dncurRow, next_pdncurRow, htcurRow, open_gap);
            next_prevRow = choose_other (next_row, a, b);
            algn_choose_affine_other (next_row, curRow, &next_dncurRow, &next_pdncurRow, d, e);
            start_row = final_row;
            final_row = seq1_len;
            start_column = 1;
            length = seq2_len - 1;
            to_go_dirMtx = dirMtx + (seq2_len * start_row);
            next_row =
                algn_fill_extending_left_affine (seq1, precalcMtx, seq1_len, seq2_len, 
                                              next_row, next_prevRow, to_go_dirMtx, c, start_row, final_row, 
                                              start_column, length, next_dncurRow, next_pdncurRow, htcurRow, 
                                              open_gap);
            next_prevRow = choose_other (next_row, a, b);
        }
    }
    return (next_prevRow[seq2_len - 1]);
}
/******************************************************************************/

/** Fill parallel must have been called before */
static inline void
fill_moved (int seq3_len, const int *prev_m, const int *upper_m, 
            const int *diag_m, const int *seq1_gap_seq3, const int *gap_seq2_seq3, 
            const int *seq1_seq2_seq3, int *curRow, DIRECTION_MATRIX *dirMtx) {
    int k, tmp0, tmp1, tmp;
    for (k = 1; k < seq3_len; k++) {
        tmp0 = upper_m[k] + seq1_gap_seq3[k];
        if (tmp0 < curRow[k]) {
            curRow[k] = tmp0;
            dirMtx[k] = ALIGN13;
        }
        tmp = prev_m[k] + gap_seq2_seq3[k];
        if (tmp < curRow[k]) {
            curRow[k] = tmp;
            dirMtx[k] = ALIGN23;
        }
        tmp1 = diag_m[k] + seq1_seq2_seq3[k];
        if (tmp1 < curRow[k]) {
            curRow[k] = tmp1;
            dirMtx[k] = ALIGNALL;
        }
    }
}

inline void
fill_parallel (int seq3_len, const int *prev_m, const int *upper_m, 
               const int *diag_m, int seq1_gap_gap, int gap_seq2_gap, int seq1_seq2_gap, int *curRow, 
               DIRECTION_MATRIX *dirMtx) {
    int k, tmp1, tmp;
    for (k = 0; k < seq3_len; k++) {
        curRow[k] = upper_m[k] + seq1_gap_gap;
        dirMtx[k] = GAP23;
        tmp = prev_m[k] + gap_seq2_gap;
        if (tmp < curRow[k]) {
            curRow[k] = tmp;
            dirMtx[k] = GAP13;
        }
        tmp1 = diag_m[k] + seq1_seq2_gap;
        if (tmp1 < curRow[k]) {
            curRow[k] = tmp1;
            dirMtx[k] = ALIGN12;
        }
    }
}

/*
 * @param seq1 is a pointer to the sequence seq1 (vertical).
 * @param seq2 (depth) is defined in the same way. 
 * @param precalcMtx is a pointer to the three dimensional matrix that holds
 *  the alignment values for all the combinations of the alphabet of sequences
 *  seq1, seq2 and seq3, with the sequence seq3 (see cm_precalc_4algn_3d for more
 *  information). 
 * @param seq1_len, @param seq2_len and @param seq3_len are the lengths of the three sequences
 *  to be aligned
 * @param *curRow is the first element of the alignment cube that will
 *  hold the matrix of the dynamic programming algorithm 
 * @param dirMtx does the same job, holding the direction information for the backtrace. 
 * @param uk is the value of the Ukkonen barriers (not used in this version of the program).
 *
 * consider all combinations
 * seq1, gap, gap   -> const for plane
 * gap, seq2, gap   -> const const per row
 * seq1, seq2, gap  -> const const per row
 * gap, seq2, seq3  -> vector (changes on each row)
 * seq1, gap, seq3  -> vector (change per plane)
 * seq1, seq2, seq3 -> vector (changes on each row)
 * gap, gap, seq3   -> vector (the last one to be done, not parallelizable
 *
 */
int
algn_fill_cube (const seq_p seq1, const seq_p seq2, const int *precalcMtx, 
                int seq1_len, int seq2_len, int seq3_len, int *curRow, DIRECTION_MATRIX *dirMtx, 
                int uk, int gap, int alphSize) {
    if (DEBUG_CALL_ORDER) {
        printf("  --algn_fill_cube\n");
    }
    SEQT *seq1_p, *seq2_p;

    /* Each of the following arrays hold some precalculated value for the
     * sequence seq3 which is not passed as argument. 
     */
    const int *gap_seq2_seq3;     /* Align a gap and the current base of seq2 with seq3 */
    const int *seq1_gap_seq3;     /* Align the current base of seq1 and a gap with seq3 */
    const int *seq1_seq2_seq3;    /* Align the current bases of seq1 and seq2 with seq3 */
    const int *gap_gap_seq3;      /* Align two gaps with seq3 */
    
    /* Each of the following arrays hold the arrays of the three dimensional
     * matrix that are located around the row that is filled on each iteration.
     * These rows are already filled in some previous iteration and used in
     * the dynamic programming matrix. 
     */
    int *upper_m;       /* The row in the upper plane of the cube */
    int *prev_m;        /* The row behind the current row in the same plane */
    int *diag_m;        /* The upper_m relative to prev_m */
    int *tmp_curRow;    /* A temporary pointer to the row that is being filled
                         * currently 
                         */
    DIRECTION_MATRIX *tmp_dirMtx;       /* Same as previous for dirMtx */
    int i, j, k, tmp;

    seq1_p = seq_get_begin (seq1);
    seq2_p = seq_get_begin (seq2);
    tmp_dirMtx = dirMtx;
    tmp_curRow = curRow;
    upper_m = curRow + seq3_len;
    diag_m = curRow;
    if (DEBUG_MAT) {
        printf ("Three dimensional sequence alignment matrix.\n");
    }


    /****************************** Fill the first plane only at the beginning, this is special ******************************/
    
    curRow[0] = 0;              /* Fill the first cell, of course to 0 */
    dirMtx[0] = ALIGNALL;

    /* Fill first row based on precalculated row.
     * The first row consists of aligning seq3 with gaps, we have that
     * precalculated, so all we really need is to add up that vector.
     */
    gap_gap_seq3 = cm_get_row_precalc_3d (precalcMtx, seq3_len, alphSize, gap, gap);
    for (i = 1; i < seq3_len; i++) {
        curRow[i] = curRow[i - 1] + gap_gap_seq3[i];
        dirMtx[i] = GAP12;
    }

    prev_m = curRow;
    curRow += seq3_len;
    dirMtx += seq3_len;

    /* Finish filling the first plane.
     * In this plane filling, all we really need to deal with is aligning seq2
     * and seq3, as the first plane holds the inital gap of seq1. */
    for (i = 1; i < seq2_len; i++, prev_m += seq3_len, curRow += seq3_len, dirMtx += seq3_len) {
        gap_seq2_seq3 = cm_get_row_precalc_3d (precalcMtx, seq3_len, alphSize, gap, seq2_p[i]);

        /** Fill the first cell with the cost of extending the gap from the
         * previous row */
        curRow[0] = prev_m[0] + gap_seq2_seq3[0];
        dirMtx[0] = GAP13;
        /* Everyone else requires the three comparisons we used when filling
         * rows as usual in a two dimensional alignment. Note that this code
         * is almost the same as algn_fill_row, so if something is modified
         * there, there will be need of modifying it in the same way here. */
        /* TODO: Add the ukkonen barriers */
        for (j = 1; j < seq3_len; j++) {
            curRow[j] = prev_m[j] + gap_seq2_seq3[0];
            dirMtx[j] = GAP13;
            tmp = prev_m[j - 1] + gap_seq2_seq3[j];
            if (tmp < curRow[j]) {
                curRow[j] = tmp;
                dirMtx[j] = ALIGN23;
            }
            tmp = curRow[j - 1] + gap_gap_seq3[j];
            if (tmp < curRow[j]) {
                curRow[j] = tmp;
                dirMtx[j] = GAP12;
            }
        }
    }
    if (DEBUG_COST_M) {  /* Printing the cost matrix */
        int *tmp_curRow_debug;
        tmp_curRow_debug = tmp_curRow;
        printf ("\n");
        for (i = 0; i < seq2_len; i++) {
            for (int l = seq2_len - i; l > 1; l--) {
                printf("  ");
            }
            for (j = 0; j < seq3_len; j++)
                printf ("%-6d", tmp_curRow_debug[j]);
            tmp_curRow_debug += seq2_len;
            printf ("\n");
        }
        printf ("\n");
    }
    /****************************** Finished the first plane filling ******************************/



    /****************************** Fill plane by plane ******************************/
    curRow = tmp_curRow + (seq3_len * seq2_len);
    dirMtx = tmp_dirMtx + (seq3_len * seq2_len);
    diag_m = tmp_curRow;
    upper_m = tmp_curRow + seq3_len;
    prev_m = curRow - seq3_len;
    for (i = 1; i < seq1_len; i++) { /* For each plane */
        int seq1_it; /* The element in seq1 represented by this plane */
        seq1_it = seq1_p[i];
        seq1_gap_seq3 = cm_get_row_precalc_3d (precalcMtx, seq3_len, alphSize, seq1_it, gap);
        /* Filling the first row of the current plane. */
        {
            /* This requires only three operations, equivalent to the
             * 2-dimensional alignment (the three for loops) */
            curRow[0] = diag_m[0] + seq1_gap_seq3[0]; /* diag is upper in this step */
            dirMtx[0] = GAP23;
            if (DEBUG_COST_M) {
                printf ("%-6d", curRow[0]);
            }
            for (j = 1, k = 0; j < seq3_len; j++, k++) {
                curRow[j] = diag_m[j] + seq1_gap_seq3[0];
                dirMtx[j] = GAP23;
                tmp = diag_m[k] + seq1_gap_seq3[j];
                if (tmp < curRow[j]) {
                    curRow[j] = tmp;
                    dirMtx[j] = ALIGN13;
                }
                tmp = gap_gap_seq3[j] + curRow[k];
                if (tmp < curRow[j]) {
                    curRow[j] = tmp;
                    dirMtx[j] = GAP12;
                }
                if (DEBUG_COST_M) {
                    printf ("%-6d", curRow[j]);
                }
            }
            if (DEBUG_COST_M) {
                printf ("\n");
            }
            /* Now we should move to the next row to continue filling the matrix */
            dirMtx += seq3_len;
            curRow += seq3_len;
        }
        /* Now, go on with the rest of the rows.  On each row, curRow is the row
         * being constructed, prev_m is the previous row in the same horizontal
         * plane, upper_m is the previous row in the vertical plane and diag_m
         * is the row in the previous planes (vertical and horizontal).
         */
        for (j = 1; j < seq2_len; j++, diag_m += seq3_len, 
                upper_m += seq3_len, prev_m += seq3_len, curRow += seq3_len, 
                dirMtx += seq3_len) {
            /* We first set the vectors that are needed */
            int seq2_it;
            seq2_it = seq2_p[j];
            gap_seq2_seq3 = cm_get_row_precalc_3d (precalcMtx, seq3_len, alphSize, gap, seq2_it);
            seq1_seq2_seq3 = cm_get_row_precalc_3d (precalcMtx, seq3_len, alphSize, seq1_it, seq2_it);
            fill_parallel (seq3_len, prev_m, upper_m, diag_m, seq1_gap_seq3[0], gap_seq2_seq3[0], 
                    seq1_seq2_seq3[0], curRow, dirMtx);
            fill_moved (seq3_len, prev_m - 1, upper_m - 1, diag_m - 1, seq1_gap_seq3, 
                        gap_seq2_seq3, seq1_seq2_seq3, curRow, dirMtx);
            /* In the final step we run over the array filling the self check.
             * */
            if (DEBUG_COST_M) {
                printf ("%-6d", curRow[0]);
            }
            for (k = 1; k < seq3_len; k++) {
                tmp = curRow[k - 1] + gap_gap_seq3[k];
                if (tmp < curRow[k]) {
                    curRow[k] = tmp;
                    dirMtx[k] = GAP12;
                }
                if (DEBUG_COST_M) {
                    printf ("%-6d", curRow[k]);
                }
            }
            if (DEBUG_COST_M) {
                printf ("\n");
            }
        }
        if (DEBUG_COST_M) {
            printf ("\n");
        }
    }
    return (curRow[-1]); /** We return the last item in the previous row */
}

/* Same as the previous function but with Ukkonen barriers turned on. The
 * additional parameters are:
 * @param w is the maximum width to be filled.
 * @param d is the maximum depth to be filled
 * @param h is the maximum height to be filled.
 * TODO: Finish this implementation, I will stop now to test the sequence
 * analysis procedures in the rest of POY.
 * */
inline int
algn_fill_cube_ukk (const seq_p seq1, const seq_p seq2, const int *precalcMtx, 
                    int seq1_len, int seq2_len, int seq3_len, int *curRow, DIRECTION_MATRIX *dirMtx, int uk, 
                    int gap, int alphSize, int w, int d, int h) {
    SEQT *seq1_p, *seq2_p;
    /* Each of the following arrays hold some precalculated value for the
     * sequence seq3 which is not passed as argument. */
    const int *gap_seq2_seq3;     /** Align a gap and the current base of seq2 with seq3 */
    const int *seq1_gap_seq3;     /** Align the current base of seq1 and a gap with seq3 */
    const int *seq1_seq2_seq3;    /** Align the current bases of seq1 and seq2 with seq3 */
    const int *gap_gap_seq3;      /** Align two gaps with seq3 */
    /* Each of the following arrays hold the arrays of the three dimensional
     * matrix that are located around the row that is filled on each iteration.
     * These rows are already filled in some previous iteration and used in
     * the dynamic progracurRowing matrix. */
    int *upper_m;       /** The row in the upper plane of the cube */
    int *prev_m;        /** The row behind the current row in the same plane */
    int *diag_m;        /** The upper_m relative to prev_m */
    int *tmp_curRow;        /** A temporary pointer to the row that is being filled
                        currently */
    DIRECTION_MATRIX *tmp_dirMtx;       /** Same as previous for dirMtx */
    int i, j, k, tmp;

    seq1_p = seq_get_begin (seq1);
    seq2_p = seq_get_begin (seq2);
    tmp_dirMtx = dirMtx;
    tmp_curRow = curRow;
    upper_m = curRow + seq3_len;
    diag_m = curRow;
    if (DEBUG_MAT)
        printf ("Three dimensional sequence alignment matrix.\n");
    /* Fill the first plane only at the beginning, this is special */
    {
        curRow[0] = 0;              /* Fill the first cell, of course to 0 */
        dirMtx[0] = ALIGNALL;

        /* Fill first row based on precalculated row.
         * The first row consists of aligning seq3 with gaps, we have that
         * precalculated, so all we really need is to add up that vector.*/
        gap_gap_seq3 = cm_get_row_precalc_3d (precalcMtx, seq3_len, alphSize, gap, gap);
        for (i = 1; i < seq3_len; i++) {
            curRow[i] = curRow[i - 1] + gap_gap_seq3[i];
            dirMtx[i] = GAP12;
        }

        prev_m = curRow;
        curRow += seq3_len;
        dirMtx += seq3_len;

        /* Finish filling the first plane.
         * In this plane filling, all we really need to deal with is aligning seq2
         * and seq3, as the first plane holds the inital gap of seq1. */
        for (i = 1; i < seq2_len; i++, prev_m += seq3_len, curRow += seq3_len, dirMtx += seq3_len) {
            gap_seq2_seq3 = cm_get_row_precalc_3d (precalcMtx, seq3_len, alphSize, gap, seq2_p[i]);

            /** Fill the first cell with the cost of extending the gap from the
             * previous row */
            curRow[0] = prev_m[0] + gap_seq2_seq3[0];
            dirMtx[0] = GAP13;
            /* Everyone else requires the three comparisons we used when filling
             * rows as usual in a two dimensional alignment. Note that this code
             * is almost the same as algn_fill_row, so if something is modified
             * there, there will be need of modifying it in the same way here. */
            /* TODO: Add the ukkonen barriers */
            for (j = 1; j < seq3_len; j++) {
                curRow[j] = prev_m[j] + gap_seq2_seq3[0];
                dirMtx[j] = GAP13;
                tmp = prev_m[j - 1] + gap_seq2_seq3[j];
                if (tmp < curRow[j]) {
                    curRow[j] = tmp;
                    dirMtx[j] = ALIGN23;
                }
                tmp = curRow[j - 1] + gap_gap_seq3[j];
                if (tmp < curRow[j]) {
                    curRow[j] = tmp;
                    dirMtx[j] = GAP12;
                }
            }
        }
        if (DEBUG_COST_M) {  /* Printing the cost matrix */
            int *tmp_curRow_debug;
            tmp_curRow_debug = tmp_curRow;
            for (i = 0; i < seq2_len; i++) {
                for (int l = seq2_len; l > 1; l++) {
                    printf("  ");
                }
                for (j = 0; j < seq3_len; j++)
                    printf ("%d\t", tmp_curRow_debug[j]);
                tmp_curRow_debug += seq2_len;
                printf ("\n");
            }
            printf ("\n");
        }
    } /* Finished the first plane filling */

    /* Fill plane by plane */
    curRow = tmp_curRow + (seq3_len * seq2_len);
    dirMtx = tmp_dirMtx + (seq3_len * seq2_len);
    diag_m = tmp_curRow;
    upper_m = tmp_curRow + seq3_len;
    prev_m = curRow - seq3_len;
    for (i = 1; i < seq1_len; i++) { /* For each plane */
        int seq1_it; /* The element in seq1 represented by this plane */
        seq1_it = seq1_p[i];
        seq1_gap_seq3 = cm_get_row_precalc_3d (precalcMtx, seq3_len, alphSize, seq1_it, gap);
        /* Filling the first row of the current plane. */
        {
            /* This requires only three operations, equivalent to the
             2-dimensional alignment (the three for loops) */
            curRow[0] = diag_m[0] + seq1_gap_seq3[0]; /* diag is upper in this step */
            dirMtx[0] = GAP23;
            if (DEBUG_DIR_M)
                printf ("%d\t", curRow[0]);
            for (j = 1, k = 0; j < seq3_len; j++, k++) {
                curRow[j] = diag_m[j] + seq1_gap_seq3[0];
                dirMtx[j] = GAP23;
                tmp = diag_m[k] + seq1_gap_seq3[j];
                if (tmp < curRow[j]) {
                    curRow[j] = tmp;
                    dirMtx[j] = ALIGN13;
                }
                tmp = gap_gap_seq3[j] + curRow[k];
                if (tmp < curRow[j]) {
                    curRow[j] = tmp;
                    dirMtx[j] = GAP12;
                }
                if (DEBUG_DIR_M)
                    printf ("%d\t", curRow[j]);
            }
            if (DEBUG_DIR_M)
                printf ("\n");
            /* Now we should move to the next row to continue filling the matrix
             * */
            dirMtx += seq3_len;
            curRow += seq3_len;
        }
        /* Now, go on with the rest of the rows.  On each row, curRow is the row
         * being constructed, prev_m is the previous row in the same horizontal
         * plane, upper_m is the previous row in the vertical plane and diag_m
         * is the row in the previous planes (vertical and horizontal).
         */
        for (j = 1; j < seq2_len; j++, diag_m += seq3_len, 
                upper_m += seq3_len, prev_m += seq3_len, curRow += seq3_len, 
                dirMtx += seq3_len) {
            /* We first set the vectors that are needed */
            int seq2_it;
            seq2_it = seq2_p[j];
            gap_seq2_seq3 = cm_get_row_precalc_3d (precalcMtx, seq3_len, alphSize, gap, seq2_it);
            seq1_seq2_seq3 = cm_get_row_precalc_3d (precalcMtx, seq3_len, alphSize, seq1_it, seq2_it);
            fill_parallel (seq3_len, prev_m, upper_m, diag_m, seq1_gap_seq3[0], gap_seq2_seq3[0], 
                           seq1_seq2_seq3[0], curRow, dirMtx);
            fill_moved (seq3_len, prev_m - 1, upper_m - 1, diag_m - 1, seq1_gap_seq3, 
                        gap_seq2_seq3, seq1_seq2_seq3, curRow, dirMtx);
            /* In the final step we run over the array filling the self check.
             * */
            if (DEBUG_DIR_M)
                printf ("%d\t", curRow[0]);
            for (k = 1; k < seq3_len; k++) {
                tmp = curRow[k - 1] + gap_gap_seq3[k];
                if (tmp < curRow[k]) {
                    curRow[k] = tmp;
                    dirMtx[k] = GAP12;
                }
                if (DEBUG_DIR_M)
                    printf ("%d\t", curRow[k]);
            }
            if (DEBUG_DIR_M)
                printf ("\n");
        }
        if (DEBUG_DIR_M)
            printf ("\n");
    }
    return (curRow[-1]); /** We return the last item in the previous row */
}

/** [algn_nw_limit_2d performs a pairwise
 *  alignment of the subsequences of seq1 and seq2 starting in position st_seq1
 *  and st_seq2, respectively, with length len_seq1 and len_seq2 using the
 *  transformation cost matrix cstMtx and the alignment matrices nw_mtxs.
 */
/** TODO: st_seq1 and st_seq2 are unused??? Also, limit defined here seems to be defined in sequence.ml but 
 *        never used. It's only call traces back to algn_CAML_limit_2, which, in turn, seems never to be called? 
 */
static inline int
algn_nw_limit_2d (const seq_p seq1, const seq_p seq2, const cost_matrices_2d_p costMtx, 
                  nw_matrices_p nw_mtxs, int deltawh, int st_seq1, int len_seq1, 
                  int st_seq2, int len_seq2) {
    const SEQT *sseq1, *sseq2;
    int *curRow, *precalcMtx, seq1_len, seq2_len;
    DIRECTION_MATRIX *dirMtx;
    sseq1 = seq_get_begin (seq1);
    sseq2 = seq_get_begin (seq2);
    curRow = mat_get_2d_nwMtx (nw_mtxs);
    dirMtx = mat_get_2d_direct (nw_mtxs);
    seq1_len = seq_get_len (seq1);
    seq2_len = seq_get_len (seq2);

    int *cost;           // The transformation cost matrix.
    SEQT *median;        /** The matrix of possible medians between elements in the
                          *  alphabet. The best possible medians according to the cost
                          *  matrix.
                          */
    int *worst;          /* Missing in 3d */
    int *prepend_cost;   /* Missing in 3d */
    int *tail_cost;      /* Missing in 3d */


    precalcMtx = mat_get_2d_prec (nw_mtxs);
    cm_precalc_4algn (costMtx, nw_mtxs, seq2); // returns precalculated cost matrix (in matrices) computed using sequence from seq2.
                                               // seq2 bases will be column heads of that matrix
    if (cm_get_affine_flag (costMtx)) {
        return
            algn_fill_plane_2_affine (seq1, precalcMtx, seq1_len, seq2_len, curRow, dirMtx, costMtx, 50, 
                                   (len_seq1 - len_seq2) + 50, deltawh, curRow + (2 * seq2_len), 
                                   curRow + (4 * seq2_len));
                // TODO: why all the 50s here and below? It looks like it's a default
                // starting value for the matrix width/height
    } else {
        return algn_fill_plane_2 (seq1, precalcMtx, seq1_len, seq2_len, curRow, dirMtx, costMtx, 50, 
                              (len_seq1 - len_seq2) + 50, deltawh);
    }
}

/** TODO: can probably eliminate either this or algn_nw_limit_2d, since
 *  both seem to be doing the same thing
 */
/** seq1 must be longer!!! */
int
algn_nw_2d (const seq_p seq1, const seq_p seq2, const cost_matrices_2d_p costMtx, 
         nw_matrices_p nw_mtxs, int deltawh) {
    // deltawh is the size of the direction matrix, and was determined by the following algorithm:
    // let dif = seq1len - seq2len
    // let lower_limit = seq1len * .1
    // if deltawh has no value
    //    then if dif < lower_limit
    //            then (lower_limit / 2)
    //            else 2
    //    else if dif < lower_limit
    //            then lower_limit
    //            else v

    // m and costMtx come from OCAML, so much be allocated in Haskell. Must
    // Determine correct size.

    // at this point, gap is already set at beginning of seq
    // bases are set as bit streams, with gap as most-significant bit.
    if(DEBUG_NW) {
        printf("---algn_nw_2d\n");
        seq_print(seq1, 1);
        seq_print(seq2, 2);
        print_matrices(nw_mtxs, costMtx->lcm);
    }


    int seq1_len, seq2_len;
    seq1_len = seq_get_len (seq1);
    seq2_len = seq_get_len (seq2);
    assert (seq1_len >= seq2_len);
    return algn_nw_limit_2d (seq1, seq2, costMtx, nw_mtxs, deltawh, 0, seq1_len, 0, seq2_len);
}

int
algn_nw_3d (const seq_p seq1, const seq_p seq2, const seq_p seq3, 
            const cost_matrices_3d_p c, nw_matrices_p m, int w) {
    const SEQT *sseq1, *sseq2, *sseq3;
    int *curRow, *precalcMtx, seq1_len, seq2_len, seq3_len, gap, res;
    DIRECTION_MATRIX *dirMtx;
   /* 
    sseq1 = seq_get_begin (seq1);
    sseq2 = seq_get_begin (seq2);
    sseq3 = seq_get_begin (seq3);
    */
    mat_setup_size (m, seq_get_len (seq2), seq_get_len (seq3), seq_get_len (seq1), 
                    w, c->lcm);
    curRow     = mat_get_3d_matrix (m);
    dirMtx     = mat_get_3d_direct (m);
    precalcMtx = mat_get_3d_prec (m);
    seq1_len = seq_get_len (seq1);
    seq2_len = seq_get_len (seq2);
    seq3_len = seq_get_len (seq3);
    gap      = cm_get_gap_3d (c);
    cm_precalc_4algn_3d (c, precalcMtx, seq3);
    /* TODO Check how is this ukkonen barrier affecting this fill cube, the w
     * was called uk */
    res = algn_fill_cube (seq1, seq2, precalcMtx, seq1_len, seq2_len, seq3_len, curRow, dirMtx, w, 
                          gap, c->alphSize);
    return res;
}

int
algn_calculate_from_2_aligned (seq_p seq1, seq_p seq2, cost_matrices_2d_p c, int *matrix) {
    int i, res = 0, gap_opening, gap_row = 0;
    SEQT gap, seq1b, seq2b;
    gap = cm_get_gap_2d (c);
    /* We initialize i to the proper location */
    seq1b = seq_get_element (seq1, 0);
    seq2b = seq_get_element (seq2, 0);
    if ((c->combinations && (gap & seq1b) && (gap & seq2b)) ||
            (!c->combinations && (gap == seq1b) && (gap == seq2b)))
        i = 1;
    else i = 0;
    gap_opening = cm_get_gap_opening_parameter (c);
    assert ((seq_get_len (seq1)) == (seq_get_len (seq2)));
    for (; i < seq_get_len (seq1); i++) {
        seq1b = seq_get_element (seq1, i);
        seq2b = seq_get_element (seq2, i);
        if (0 == gap_row) { /* We have no gaps */
            if ((c->combinations && (seq1b & gap) && !(seq2b & gap)) ||
                        ((!c->combinations) && (seq1b == gap)))
            {
                res += gap_opening;
                gap_row = 1;
            } else if ((c->combinations && (seq2b & gap) && !(seq1b & gap)) ||
                        ((!c->combinations) && (seq2b == gap))) {
                res += gap_opening;
                gap_row = 2;
            }
        }
        else if (1 == gap_row) { /* We are in seq1's block of gaps */
            if ((c->combinations && !(seq1b & gap)) ||
                        ((!c->combinations) && (seq1b != gap))) {
                if ((c->combinations && (seq2b & gap) && !(seq1b & gap)) ||
                        ((!c->combinations) && (seq2b == gap))) {
                    res += gap_opening;
                    gap_row = 2;
                }
                else gap_row = 0;
            }
        }
        else { /* We are in seq2's block of gaps */
            assert (2 == gap_row);
            if ((c->combinations && !(seq2b & gap)) ||
                        ((!c->combinations) && (seq2b != gap))) {
                if ((c->combinations && (seq1b & gap)) ||
                        ((!c->combinations) && (seq1b == gap))) {
                    res += gap_opening;
                    gap_row = 1;
                }
                else gap_row = 0;
            }
        }
        res += (cm_calc_cost (matrix, seq_get_element (seq1, i), seq_get_element (seq2, i), c->lcm));
    }
    return (res);
}

int
algn_worst_2 (seq_p seq1, seq_p seq2, cost_matrices_2d_p c) {
    return (algn_calculate_from_2_aligned (seq1, seq2, c, c->worst));
}

int
algn_verify_2 (seq_p seq1, seq_p seq2, cost_matrices_2d_p c) {
    return (algn_calculate_from_2_aligned (seq1, seq2, c, c->cost));
}

/*
value
algn_CAML_worst_2 (value seq1, value seq2, value c) {
    CAMLparam3(seq1, seq2, c);
    cost_matrices_2d_p tc;
    int res;
    seq_p seq1_p, seq2_p;
    Seq_custom_val(seq1_p, seq1);
    Seq_custom_val(seq2_p, seq2);
    tc = Cost_matrix_struct(c);
    res = algn_worst_2 (seq1_p, seq2_p, tc);
    CAMLreturn(Val_int(res));
}

value
algn_CAML_verify_2 (value seq1, value seq2, value c) {
    CAMLparam3(seq1, seq2, c);
    cost_matrices_2d_p tc;
    int res;
    seq_p seq1_p, seq2_p;
    Seq_custom_val(seq1_p, seq1);
    Seq_custom_val(seq2_p, seq2);
    tc = Cost_matrix_struct(c);
    res = algn_verify_2 (seq1_p, seq2_p, tc);
    CAMLreturn(Val_int(res));
}

value
algn_CAML_simple_2 (value seq1, value seq2, value c, value a, value deltawh) {
    CAMLparam5(seq1, seq2, c, a, deltawh);
    printf("algn_CAML_simple_2\n");
    seq_p seq1_p, seq2_p;
    int res;
    cost_matrices_2d_p tc;
    nw_matrices_p ta;
    tc = Cost_matrix_struct(c);
    cm_print (tc);
    ta = Matrices_struct(a);
    Seq_custom_val(seq1_p, seq1);
    Seq_custom_val(seq2_p, seq2);
    mat_setup_size (ta, seq_get_len(seq1_p), seq_get_len(seq2_p), 0, 0, \
            cm_get_lcm(tc));
#ifdef DEBUG_ALL_ASSERTIONS
    _algn_max_matrix = ta->matrix + ta->len_eff;
    _algn_max_direction = ta->matrix_d + ta->len;
#endif
    res = algn_nw_2d (seq1_p, seq2_p, tc, ta, Int_val(deltawh));
    CAMLreturn(Val_int(res));
}

value
algn_CAML_limit_2 (value seq1, value seq2, value c, value a, value w, value h, \
        value seq1_st, value seq2_st, value seq1_len, value seq2_len) {
    CAMLparam5(seq1, seq2, c, a, w);
    CAMLxparam5(h, seq1_st, seq2_st, seq1_len, seq2_len);
    seq_p seq1_p, seq2_p;
    int res, cw;
    cost_matrices_2d_p tc;
    nw_matrices_p ta;
    cw = Int_val(w);
    tc = Cost_matrix_struct(c);
    ta = Matrices_struct(a);
    Seq_custom_val(seq1_p, seq1);
    Seq_custom_val(seq2_p, seq2);
    mat_setup_size (ta, seq_get_len(seq1_p), seq_get_len(seq2_p), 0, 0, \
            cm_get_lcm(tc));
    // TODO: Fix this deltaw binding
    res = algn_nw_limit_2d (seq1_p, seq2_p, tc, ta, Int_val(w), 
            Int_val(seq1_st), Int_val(seq1_len), Int_val(seq2_st), Int_val(seq2_len));
    CAMLreturn(Val_int(res));
}


value
algn_CAML_limit_2_bc (value *argv, int argn) {
    return (algn_CAML_limit_2 (argv[0], argv[1], argv[2], argv[3], argv[4], \
                argv[5], argv[6], argv[7], argv[8], argv[9]));
}

value
algn_CAML_simple_3 (value seq1, value seq2, value seq3, value c, value a, value uk) {
    CAMLparam5(seq1, seq2, seq3, c, a);
    CAMLxparam1(uk);
    seq_p seq1_p, seq2_p, seq3_p;
    int res;
    cost_matrices_3d_p tc;
    nw_matrices_p ta;
    tc = Cost_matrix_struct_3d(c);
    ta = Matrices_struct(a);
    Seq_custom_val(seq1_p, seq1);
    Seq_custom_val(seq2_p, seq2);
    Seq_custom_val(seq3_p, seq3);
    res = algn_nw_3d (seq1_p, seq2_p, seq3_p, tc, ta, Int_val(uk));
    CAMLreturn(Val_int(res));
}

value
algn_CAML_simple_3_bc (value *argv, int argn) {
    return (algn_CAML_simple_3 (argv[0], argv[1], argv[2], argv[3], argv[4], \
                argv[5]));
}
*/

void
algn_print_bcktrck_2d (const seq_p seq1, const seq_p seq2, 
              const nw_matrices_p m) {
    int i, j;
    DIRECTION_MATRIX *d;
    d = mat_get_2d_direct (m);
    printf ("\n");
    for (i = 0; i < seq_get_len (seq1); i++) {
        for (j = 0; j < seq_get_len (seq2); j++) {
            printf ("%d", (int) *(d + j));
            fflush (stdout);
        }
        d += j;
        printf ("\n");
        fflush (stdout);
    }
    printf ("\n\n");
    fflush (stdout);
    return;
}

/*
value
algn_CAML_print_bcktrck (value seq1, value seq2, value matrix) {
    CAMLparam3(seq1, seq2, matrix);
    seq_p seq1c, seq2c;
    nw_matrices_p m;
    Seq_custom_val(seq1c, seq1);
    Seq_custom_val(seq2c, seq2);
    m = Matrices_struct(matrix);
    print_bcktrck (seq1c, seq2c, m);
    CAMLreturn (Val_unit);
}
*/

void
algn_print_dynmtrx_2d (const seq_p seq1, const seq_p seq2, nw_matrices_p matrices) {
    int i, j;
    /*
    const int seqLen1 = seq_get_len (seq1);
    const int seqLen2 = seq_get_len (seq2);

    const seq_p longerSeq  = seqLen1 > seqLen2 ? seq1 : seq2;
    const seq_p lesserSeq  = seqLen1 > seqLen2 ? seq2 : seq1;

    const int longerSeqLen = seqLen1 > seqLen2 ? seqLen1 : seqLen2;
    const int lesserSeqLen = seqLen1 > seqLen2 ? seqLen2 : seqLen1;
    
    const int n       = longerSeqLen + 1;
    const int m       = lesserSeqLen + 1;
    int *nw_costMtx;
    nw_costMtx = mat_get_2d_nwMtx (matrices);
    DIRECTION_MATRIX *nw_dirMtx  = mat_get_2d_direct (matrices);

    printf ("Sequence 1 length: %d\n", seqLen1);
    printf ("Sequence 2 length: %d\n", seqLen2);
    printf ("Length    Product: %d\n", seqLen1 * seqLen2);
    printf ("Length +1 Product: %d\n", n * m);
    printf ("Allocated space  : %d\n\n", matrices->len);
    
    printf("Cost matrix:\n");
    // print column heads
    printf("  x |       * ");
    for (i = 1; i < lesserSeqLen; i++) {
        printf("%7d ", lesserSeq->begin[i]);
    }
    printf("\n");
    printf(" ---+-");
    for (i = 1; i < lesserSeqLen; i++) {
      printf("--------");  
    }
    printf("\n");
    
    for (i = 0; i < longerSeqLen; i++) {
        if (i == 0) printf ("  * | ");
        else        printf (" %2d | ", longerSeq->begin[i]);
  
        for (j = 0; j < lesserSeqLen; j++) {
            // if (j == 0 && i == 0) {
            //     printf("%7d ", 0);
            // } else {
                printf ("%7d ", (int) nw_costMtx[lesserSeqLen * i + j]);
            // }
        }
        printf ("\n");
    }

    // Print direction matrix
    setlocale(LC_CTYPE, "en_US.UTF-8");

    wchar_t *name;
    printf("\n\nDirection matrix:\n");
    // print column heads
    printf("  x |       * ");
    for (i = 1; i < lesserSeqLen; i++) {
        printf("%7d ", lesserSeq->begin[i]);
    }
    printf("\n");
    printf(" ---+-");
    for (i = 1; i < lesserSeqLen + 1; i++) {
      printf("--------");  
    }
    printf("\n");


    for (i = 0; i < longerSeqLen; i++) {
        if (i == 0) printf ("  * | ");
        else        printf (" %2d | ", longerSeq->begin[i]);
  
        for (j = 0; j < lesserSeqLen; j++) {
            unsigned short dirToken = nw_dirMtx[lesserSeqLen * i + j];

            //if (dirToken & ALIGN)    printf ("A");
            //if (dirToken & DELETE)   printf ("D");
            //if (dirToken & INSERT)   printf ("I");
            //if (dirToken & ALIGN_V)  printf ("VA");
            //if (dirToken & DELETE_V) printf ("VD");
            //if (dirToken & ALIGN_H)  printf ("HA");
            //if (dirToken & INSERT_H) printf ("HI");
            //printf("\t");

            printf("    "); // leading pad
            wprintf(L"%s", dirToken & DELETE ? (wchar_t *) "\u2191" : (wchar_t *) " ");
            wprintf(L"%s", dirToken & ALIGN  ? (wchar_t *) "\u2196" : (wchar_t *) " ");
            wprintf(L"%s", dirToken & INSERT ? (wchar_t *) "\u2190" : (wchar_t*) " ");
            printf(" ");
        }
        printf ("\n");
    }

    */
      return;
}

void
algn_string_of_2d_direction (DIRECTION_MATRIX v) {
    if (v & ALIGN) printf ("A");
    if (v & DELETE) printf ("D");
    if (v & INSERT) printf ("I");
    if (v & ALIGN_V) printf ("VA");
    if (v & DELETE_V) printf ("VD");
    if (v & ALIGN_H) printf ("HA");
    if (v & INSERT_H) printf ("HI");
    return;
}

#define my_prepend(a, b) assert (a->cap > a->len); \
                        a->begin = (a->begin) - 1; \
                        a->len = 1 + a->len; \
                        *(a->begin) = b

#define my_get(a, b) (a->begin)[b]


void
algn_backtrace_2d ( const seq_p seq1, const seq_p seq2, 
               seq_p ret_seq1, seq_p ret_seq2, 
               const nw_matrices_p m, const cost_matrices_2d_p c, 
               int st_seq1, int st_seq2, 
               int swapped 
              ) {
    int l, idx_seq1, idx_seq2;
    DIRECTION_MATRIX *beg, *end;
    int new_item_for_ret_seq1 = 0;
    int new_item_for_ret_seq2 = 0;
    int shifter = 0;
    idx_seq1 = seq_get_len (seq1);
    idx_seq2 = seq_get_len (seq2);
    l = idx_seq1 * idx_seq2;
    beg = mat_get_2d_direct (m) + st_seq2; // offset by limit into matrix
    // TODO: figure out wtf this means:
    /* Stitching goes to hell now
    end = beg + (idx_seq2 * idx_seq1) + idx_seq2 - 1;
    */
    end = beg + (idx_seq1 * idx_seq2) - 1;
    l = idx_seq2;

    if (DEBUG_ALGN) {
        printf("\nst_seq1: %d\n", st_seq1);
        printf("st_seq2: %d\n", st_seq2);
        printf("idx_seq1: %d\n", idx_seq1);
        printf("idx_seq2: %d\n", idx_seq2);

        if (DEBUG_DIR_M) {
            printf("\n");
            DIRECTION_MATRIX *beg_debug;
            int i, j;
            beg_debug = beg;

            printf ("Printing a two dimensional direction matrix.\n");
            for (i = 0; i < idx_seq1; i++, beg_debug += idx_seq2) {
                for (j  = 0; j < idx_seq2; j++) {
                    algn_string_of_2d_direction (beg_debug[j]);
                    fprintf (stdout, "\t");
                    fflush (stdout);
                    end = beg_debug + j;
                }
                fprintf (stdout, "\n");
                fflush (stdout);
            }
            fprintf (stdout, "\n");
            fflush (stdout);
        }
    }

    end = beg + (idx_seq2 * (idx_seq1 - 1)) + idx_seq2 - 1;

    idx_seq1 += st_seq1;
    idx_seq2 += st_seq2;
    // The following pair of while loops are the same lines of code, each
    // has swapped INSERT and DELETE procedures, so that depending on the ordering
    // of the two sequences (swap) either INSERTING or DELETING will be preferred.
    // During the downpass and all the optimization procedures, keeping the same
    // ordering for the medians output is important to keep consistency in the
    // diagnosis at every step. In other words, if a join is performed starting
    // in any position of the tree, it is necessary to make sure that the very
    // same median would be produced if the calculation started in any of its
    // children.
    // Note that these two lines could be defined as macros, but we (Andres?) have
    // decided not to do so to keep it readable. Besides, once correct, there is
    // nothing (or very few things) to do here.
    if (!(cm_get_affine_flag (c))) { // not affine
        if (swapped) {               // swapped
            while (end >= beg) {
                if (*end & ALIGN) {
                    idx_seq1--;
                    new_item_for_ret_seq1 = my_get(seq1, idx_seq1);
                    my_prepend(ret_seq1, new_item_for_ret_seq1);
                    idx_seq2--;
                    new_item_for_ret_seq2 = my_get(seq2, idx_seq2);
                    my_prepend(ret_seq2, new_item_for_ret_seq2);
                    end -= l + 1;
                    if (DEBUG_ALGN) {
                        printf("Align:\n");
                        printf("  idx_seq1:    %d, idx_seq2:    %d\n", idx_seq1, idx_seq2);
                        printf("  new item a: %d, new item b: %d\n", *ret_seq1->begin, *ret_seq2->begin);
                    }
                }
                else if (*end & INSERT) {
                    new_item_for_ret_seq1 = cm_get_gap_2d (c);
                    my_prepend(ret_seq1, new_item_for_ret_seq1);
                    idx_seq2--;
                    new_item_for_ret_seq2 = my_get(seq2, idx_seq2);
                    my_prepend(ret_seq2, new_item_for_ret_seq2);
                    end -= 1;
                    if (DEBUG_ALGN) {
                        printf("Insert:\n");
                        printf("  idx_seq1:    %d, idx_seq2:    %d\n", idx_seq1, idx_seq2);
                        printf("  new item a: %d, new item b: %d\n", new_item_for_ret_seq1, new_item_for_ret_seq2);
                    }
                }
                else if ((*end & DELETE)) {
                    idx_seq1--;
                    new_item_for_ret_seq1 = my_get (seq1, idx_seq1);
                    my_prepend(ret_seq1, new_item_for_ret_seq1);
                    new_item_for_ret_seq2 = cm_get_gap_2d (c);
                    my_prepend(ret_seq2, new_item_for_ret_seq2);
                    end -= l;
                    if (DEBUG_ALGN) {
                        printf("Delete:\n");
                        printf("  idx_seq1:    %d, idx_seq2:    %d\n", idx_seq1, idx_seq2);
                        printf("  new item a: %d, new item b: %d\n", new_item_for_ret_seq1, new_item_for_ret_seq2);
                    }
                }
                else { // something terrible has happened!!!!
                    printf("Error. Alignment cost matrix:\n");
                    algn_print_dynmtrx_2d (seq1, seq2, m);
                    printf("*beg: %d\n", *beg);
                    printf("*end: %d\n", *end);
                    printf("beg: 0x%d\n", (unsigned int) beg);
                    printf("end: 0x%d\n", (unsigned int) end);
                    int limit = end - beg;
                    for (int i = 0; i <= limit; i++)
                    {
                         printf("%d, ", (beg[i]));
                    }
                    printf("\n");
                    assert (*end & (ALIGN | INSERT | DELETE));
                }
            }
        } else { // not affine, not swapped
            while (end >= beg) {
                if (*end & ALIGN) {
                    idx_seq1--;
                    new_item_for_ret_seq1 = my_get(seq1, idx_seq1);
                    my_prepend(ret_seq1, new_item_for_ret_seq1);
                    idx_seq2--;
                    new_item_for_ret_seq2 = my_get(seq2, idx_seq2);
                    my_prepend(ret_seq2, new_item_for_ret_seq2);
                    end -= l + 1;
                }
                else if (*end & DELETE) {
                    idx_seq1--;
                    new_item_for_ret_seq1 = my_get(seq1, idx_seq1);
                    my_prepend(ret_seq1, new_item_for_ret_seq1);
                    new_item_for_ret_seq2 = cm_get_gap_2d (c);
                    my_prepend(ret_seq2, new_item_for_ret_seq2);
                    end -= l;
                }
                else {
                    assert (*end & INSERT);
                    new_item_for_ret_seq1 = cm_get_gap_2d (c);
                    my_prepend(ret_seq1, new_item_for_ret_seq1);
                    idx_seq2--;
                    new_item_for_ret_seq2 = my_get(seq2, idx_seq2);
                    my_prepend(ret_seq2, new_item_for_ret_seq2);
                    end -= 1;
                }
            }
        }
    } else {             // affine
        if (swapped) {   // swapped
            while (end >= beg) {
                if (*end & (ALIGN << shifter)) {
                    if (0 == shifter) {
                        if (DEBUG_BT) printf ("1\t");
                        idx_seq1--;
                        new_item_for_ret_seq1 = my_get(seq1, idx_seq1);
                        my_prepend(ret_seq1, new_item_for_ret_seq1);
                        idx_seq2--;
                        new_item_for_ret_seq2 = my_get(seq2, idx_seq2);
                        my_prepend(ret_seq2, new_item_for_ret_seq2);
                        end -= l + 1;
                    } else if (SHIFT_V == shifter) {
                        if (DEBUG_BT) printf ("2\t");
                        idx_seq1--;
                        new_item_for_ret_seq1 = my_get (seq1, idx_seq1);
                        my_prepend(ret_seq1, new_item_for_ret_seq1);
                        new_item_for_ret_seq2 = cm_get_gap_2d (c);
                        my_prepend(ret_seq2, new_item_for_ret_seq2);
                        end -= l;
                        shifter = 0;
                    } else {
                        if (DEBUG_BT) printf ("3\t");
                        assert (SHIFT_H == shifter);
                        new_item_for_ret_seq1 = cm_get_gap_2d (c);
                        my_prepend(ret_seq1, new_item_for_ret_seq1);
                        idx_seq2--;
                        new_item_for_ret_seq2 = my_get(seq2, idx_seq2);
                        my_prepend(ret_seq2, new_item_for_ret_seq2);
                        end -= 1;
                        shifter = 0;
                    }
                }
                else if (*end & (INSERT << shifter)) {
                    if (0 == shifter) {
                        if (DEBUG_BT) printf ("4\t");
                        shifter = SHIFT_H;
                    } else if (SHIFT_H == shifter) {
                        if (DEBUG_BT) printf ("5\t");
                        new_item_for_ret_seq1 = cm_get_gap_2d (c);
                        my_prepend(ret_seq1, new_item_for_ret_seq1);
                        idx_seq2--;
                        new_item_for_ret_seq2 = my_get(seq2, idx_seq2);
                        my_prepend(ret_seq2, new_item_for_ret_seq2);
                        end -= 1;
                    } else {
                        if (DEBUG_BT) printf ("6\t");
                        assert (0);
                    }
                } else {
                    assert (*end & (DELETE << shifter));
                    if (0 == shifter) {
                        if (DEBUG_BT) printf ("7\t");
                        shifter = SHIFT_V;
                    } else if (SHIFT_V == shifter) {
                        if (DEBUG_BT) printf ("8\t");
                        idx_seq1--;
                        new_item_for_ret_seq1 = my_get (seq1, idx_seq1);
                        my_prepend(ret_seq1, new_item_for_ret_seq1);
                        new_item_for_ret_seq2 = cm_get_gap_2d (c);
                        my_prepend(ret_seq2, new_item_for_ret_seq2);
                        end -= l;
                    } else {
                        if (DEBUG_BT) printf ("9\t");
                        assert (0);
                    }
                }
            } // end while
        } else { // affine, not swapped
            while (end >= beg) {
                if (*end & (ALIGN << shifter)) {
                    if (0 == shifter) {
                        idx_seq1--;
                        new_item_for_ret_seq1 = my_get(seq1, idx_seq1);
                        my_prepend(ret_seq1, new_item_for_ret_seq1);
                        idx_seq2--;
                        new_item_for_ret_seq2 = my_get(seq2, idx_seq2);
                        my_prepend(ret_seq2, new_item_for_ret_seq2);
                        end -= l + 1;
                    } else if (SHIFT_V == shifter) {
                        idx_seq1--;
                        new_item_for_ret_seq1 = my_get (seq1, idx_seq1);
                        my_prepend(ret_seq1, new_item_for_ret_seq1);
                        new_item_for_ret_seq2 = cm_get_gap_2d (c);
                        my_prepend(ret_seq2, new_item_for_ret_seq2);
                        end -= l;
                        shifter = 0;
                    } else {
                        assert (SHIFT_H == shifter);
                        new_item_for_ret_seq1 = cm_get_gap_2d (c);
                        my_prepend(ret_seq1, new_item_for_ret_seq1);
                        idx_seq2--;
                        new_item_for_ret_seq2 = my_get(seq2, idx_seq2);
                        my_prepend(ret_seq2, new_item_for_ret_seq2);
                        end -= 1;
                        shifter = 0;
                    }
                } else if (*end & (DELETE << shifter)) {
                    if (0 == shifter) {
                        shifter = SHIFT_V;
                    } else if (SHIFT_V == shifter) {
                        idx_seq1--;
                        new_item_for_ret_seq1 = my_get (seq1, idx_seq1);
                        my_prepend(ret_seq1, new_item_for_ret_seq1);
                        new_item_for_ret_seq2 = cm_get_gap_2d (c);
                        my_prepend(ret_seq2, new_item_for_ret_seq2);
                        end -= l;
                    } else {
                        assert (0);
                    }
                } else {
                    assert (*end & (INSERT << shifter));
                    if (0 == shifter)
                        shifter = SHIFT_H;
                    else if (SHIFT_H == shifter) {
                        new_item_for_ret_seq1 = cm_get_gap_2d (c);
                        my_prepend(ret_seq1, new_item_for_ret_seq1);
                        idx_seq2--;
                        new_item_for_ret_seq2 = my_get(seq2, idx_seq2);
                        my_prepend(ret_seq2, new_item_for_ret_seq2);
                        end -= 1;
                    }
                    else {
                        assert (0);
                    }
                }
            } // end while
        }
    }
    return;
}

char *
algn_string_of_3d_direction (char v) {
    if      (v & ALIGNALL) return "ALGN-ALL";
    else if (v & ALIGN13)  return "ALGN--13";
    else if (v & ALIGN23)  return "ALGN--23";
    else if (v & GAP23)    return "GAP---23";
    else if (v & GAP12)    return "GAP---12";
    else if (v & GAP13)    return "GAP---13";
    else if (v & ALIGN12)  return "ALGN--12";
    else {
        assert (0);
    }
    return "Empty";
}

void
algn_backtrace_3d ( const seq_p seq1, const seq_p seq2, const seq_p seq3, 
               seq_p ret_seq1, seq_p ret_seq2, seq_p ret_seq3, 
               const cost_matrices_3d_p c, nw_matrices_p m
             ) {
    int len_dirMtx, idx_seq1, idx_seq2, idx_seq3;
    int a_plane, a_line, a_cell;
    DIRECTION_MATRIX *beg, *end;
    idx_seq1   = seq_get_len (seq1);
    idx_seq2   = seq_get_len (seq2);
    idx_seq3   = seq_get_len (seq3);
    len_dirMtx = idx_seq1 * idx_seq2 * idx_seq3;
    a_plane    = idx_seq2 * idx_seq3; // move one plane up (so move one down seq1) TODO: check these three assertions
    a_line     = idx_seq3;            // move one line over (so move one down seq3)
    a_cell     = 1;                   // move over 1 (so move one down seq2)
    beg        = mat_get_3d_direct (m);
    if (DEBUG_DIR_M) {
        char *toprint;
        DIRECTION_MATRIX *beg_debug;
        int i, j, k;
        beg_debug = beg;
        printf ("\n\n*** Printing a three dimensional direction matrix.\n");
        printf("*** Width is shortest sequence.\n");
        printf("*** Depth is middle sequence;\n");
        printf("*** Height (# of blocks) longest sequence.\n\n");
        for (i = 0; i < idx_seq1; i++) {
            for (j  = 0; j < idx_seq2; j++) {
                for (int l = idx_seq2 - j; l > 1; l--) {
                    printf("  ");
                }
                for (k = 0 ; k < idx_seq3; k++, beg_debug++) {
                    toprint = algn_string_of_3d_direction (*beg_debug);
                    printf ("%-9s  ", toprint);
                }
                printf ("\n");
            }
            printf ("\n");
        }
    }
    end = beg + len_dirMtx - 1;
    idx_seq1--;
    idx_seq2--;
    idx_seq3--;
    while (end >= beg) {
        if (*end & ALIGNALL) {        /* A plane, line, and cell */
            seq_prepend (ret_seq1, seq_get_element (seq1, idx_seq1--));
            seq_prepend (ret_seq2, seq_get_element (seq2, idx_seq2--));
            seq_prepend (ret_seq3, seq_get_element (seq3, idx_seq3--));
            end -= a_plane + a_line + a_cell;
        } else if (*end & ALIGN13) { /* A plane and cell */
            seq_prepend (ret_seq1, seq_get_element (seq1, idx_seq1--));
            seq_prepend (ret_seq2, cm_get_gap_3d (c));
            seq_prepend (ret_seq3, seq_get_element (seq3, idx_seq3--));
            end -= a_plane + a_cell;
        } else if (*end & ALIGN23) { /* A line and cell */
            seq_prepend (ret_seq1, cm_get_gap_3d (c));
            seq_prepend (ret_seq2, seq_get_element (seq2, idx_seq2--));
            seq_prepend (ret_seq3, seq_get_element (seq3, idx_seq3--));
            end -= a_line + a_cell;
        } else if (*end & GAP23) { /* A plane */
            seq_prepend (ret_seq1, seq_get_element (seq1, idx_seq1--));
            seq_prepend (ret_seq2, cm_get_gap_3d (c));
            seq_prepend (ret_seq3, cm_get_gap_3d (c));
            end -= a_plane;
        } else if (*end & GAP12) { /* A cell */
            seq_prepend (ret_seq1, cm_get_gap_3d (c));
            seq_prepend (ret_seq2, cm_get_gap_3d (c));
            seq_prepend (ret_seq3, seq_get_element (seq3, idx_seq3--));
            end -= a_cell;
        } else if (*end & GAP13) { /* A line */
            seq_prepend (ret_seq1, cm_get_gap_3d (c));
            seq_prepend (ret_seq2, seq_get_element (seq2, idx_seq2--));
            seq_prepend (ret_seq3, cm_get_gap_3d (c));
            end -= a_line;
        } else if (*end & ALIGN12) { /* A plane and line */
            seq_prepend (ret_seq1, seq_get_element (seq1, idx_seq1--));
            seq_prepend (ret_seq2, seq_get_element (seq2, idx_seq2--));
            seq_prepend (ret_seq3, cm_get_gap_3d (c));
            end -= a_plane + a_line;
        }
        else {
            assert (0);
        }
    }
    return;
}

/*
value
algn_CAML_backtrack_2d (value seq1, value seq2, value seq1_p, value seq2_p, value a, \
        value c, value swap) {
    CAMLparam5(seq1, seq2, seq1_p, seq2_p, a);
    CAMLxparam2(c, swap);
    seq_p sseq1, sseq2, sseq1_p, sseq2_p;
    nw_matrices_p ta;
    cost_matrices_2d_p cc;
    ta = Matrices_struct(a);
    Seq_custom_val(sseq1, seq1);  // sseq1 is pointer to sequence seq1, or maybe a copy? No, looks like a pointer, hence 'p'
    Seq_custom_val(sseq2, seq2);
    Seq_custom_val(sseq1_p, seq1_p); // sseq1_p is pointer to seq1_p, which is empty seq struct
    Seq_custom_val(sseq2_p, seq2_p);
    cc = Cost_matrix_struct(c);
    algn_backtrace_2d (sseq1, sseq2, sseq1_p, sseq2_p, ta, cc, 0, 0, seq_get_len(sseq1), \
            seq_get_len(sseq2), Bool_val(swap), seq1, seq2);
    CAMLreturn(Val_unit);
}

value
algn_CAML_backtrack_2d_bc (value *argv, int argn) {
    return (algn_CAML_backtrack_2d (argv[0], argv[1], argv[2], argv[3], \
                argv[4], argv[5], argv[6]));
}

value
algn_CAML_backtrack_2d_limit (value seq1, value seq2, value seq1_p, \
        value seq2_p, value a, value c, value st_seq1, value st_seq2, \
        value idx_seq1, value idx_seq2, value swapped) {
    CAMLparam5 (seq1, seq2, seq1_p, seq2_p, a);
    CAMLxparam5 (c, st_seq1, st_seq2, idx_seq1, idx_seq2);
    CAMLxparam1 (swapped);
    seq_p sseq1, sseq2, sseq1_p, sseq2_p;
    nw_matrices_p ta;
    cost_matrices_2d_p cc;
    ta = Matrices_struct(a);
    Seq_custom_val(sseq1, seq1);
    Seq_custom_val(sseq2, seq2);
    Seq_custom_val(sseq1_p, seq1_p);
    Seq_custom_val(sseq2_p, seq2_p);
    cc = Cost_matrix_struct(c);
    algn_backtrace_2d (sseq1, sseq2, sseq1_p, sseq2_p, ta, cc, Int_val(st_seq1), \
            Int_val(st_seq2), Int_val(idx_seq1), Int_val(idx_seq2), 
            Bool_val(swapped), seq1, seq2);
    CAMLreturn (Val_unit);
}

value
algn_CAML_backtrack_2d_limit_bc (value *argv, int argn) {
    return (algn_CAML_backtrack_2d_limit (argv[0], argv[1], argv[2], argv[3], \
                argv[4], argv[5], argv[6], argv[7], argv[8], argv[9], argv[10]));
}

value
algn_CAML_backtrack_3d (value seq1, value seq2, value seq3, value seq1_p, value seq2_p, \
        value seq3_p, value a, value c) {
    CAMLparam5(seq1, seq2, seq1_p, seq2_p, a);
    CAMLxparam2(seq3, seq3_p);
    seq_p sseq1, sseq2, sseq3, sseq1_p, sseq2_p, sseq3_p;
    nw_matrices_p ta;
    cost_matrices_3d_p tc;
    ta = Matrices_struct(a);
    Seq_custom_val(sseq1, seq1);
    Seq_custom_val(sseq2, seq2);
    Seq_custom_val(sseq3, seq3);
    Seq_custom_val(sseq1_p, seq1_p);
    Seq_custom_val(sseq2_p, seq2_p);
    Seq_custom_val(sseq3_p, seq3_p);
    tc = Cost_matrix_struct_3d(c);
    algn_backtrace_3d (sseq1, sseq2, sseq3, sseq1_p, sseq2_p, sseq3_p, ta, tc);
    CAMLreturn(Val_unit);
}

value
algn_CAML_backtrack_3d_bc (value *argv, int argc) {
    return (algn_CAML_backtrack_3d (argv[0], argv[1], argv[2], argv[3], \
                argv[4], argv[5], argv[6], argv[7]));
}

value
algn_CAML_align_2d (value seq1, value seq2, value c, value a, value seq1_p, \
        value seq2_p, value deltawh, value swapped)
{
    CAMLparam5(seq1, seq2, c, a, seq1_p);
    CAMLxparam3(seq2_p, deltawh, swapped);
    CAMLlocal1(res);
    res = algn_CAML_simple_2 (seq1, seq2, c, a, deltawh);
    algn_CAML_backtrack_2d (seq1, seq2, seq1_p, seq2_p, a, c, swapped);
    CAMLreturn(res);
}

value
algn_CAML_align_2d_bc (value *argv, int argn) {
    return (algn_CAML_align_2d (argv[0], argv[1], argv[2], argv[3], argv[4], \
                argv[5], argv[6], argv[7]));
}

value
algn_CAML_align_3d (value seq1, value seq2, value seq3, value c, value a, \
        value seq1_p, value seq2_p, value seq3_p, value uk) {
    CAMLlocal1(res);
    res = algn_CAML_simple_3 (seq1, seq2, seq3, c, a, uk);
    algn_CAML_backtrack_3d (seq1, seq2, seq3, seq1_p, seq2_p, seq3_p, a, c);
    return (res);
}

value
algn_CAML_align_3d_bc (value *argv, int argn) {
    return (algn_CAML_align_3d (argv[0], argv[1], argv[2], argv[3], argv[4], \
                argv[5], argv[6], argv[7], argv[8]));
}
*/

inline void
algn_get_median_2d_with_gaps (seq_p seq1, seq_p seq2, cost_matrices_2d_p m, seq_p sm) {
    SEQT *begin1, *begin2;
    int interm;
    int i;
    begin1 = seq_get_begin (seq1);
    begin2 = seq_get_begin (seq2);
    for (i = seq_get_len (seq1) - 1; i >= 0; i--) {
        interm = cm_get_median (m, begin1[i], begin2[i]);
        seq_prepend (sm, interm);
    }
    return;
}

inline void
algn_get_median_2d_no_gaps (seq_p seq1, seq_p seq2, cost_matrices_2d_p m, seq_p sm) {
    SEQT *begin1, *begin2;
    int interm;
    int i;
    begin1 = seq_get_begin (seq1);
    begin2 = seq_get_begin (seq2);
    for (i = seq_get_len (seq1) - 1; i >= 0; i--) {
        interm = cm_get_median (m, begin1[i], begin2[i]);
        if (interm != cm_get_gap_2d (m))
            seq_prepend (sm, interm);
    }
    seq_prepend (sm, cm_get_gap_2d (m));
    return;
}

void
algn_remove_gaps (int gap, seq_p s) {
    int i, len;
    len = seq_get_len (s);
    SEQT *source, *destination;
    int newlen = 0;
    source = destination = s->end;
    for (i = len - 1; i >= 0; i--) {
        if (gap != *source) {
            *destination = *source;
            destination--;
            newlen++;
        }
        source--;
    }
    s->len = newlen;
    s->begin = destination + 1;
    /* We restore the leading gap */
    seq_prepend (s, gap);
    return;
}

void
algn_correct_blocks_affine (int gap, seq_p s, seq_p a, seq_p b) {
    int i, len, ab, bb, sb, extending_gap, 
        inside_block = 0, prev_block = 0;
    len = seq_get_len (s);
    extending_gap = 0;
    inside_block = 0;
    for (i = 0; i < len; i++) {
        ab = seq_get_element (a, i);
        bb = seq_get_element (b, i);
        sb = seq_get_element (s, i);
        if (i > 2) {

        }
        if (!inside_block && (!(ab & gap) || !(bb & gap)))
            inside_block = 0;
        else if (inside_block && ((!(ab & gap)) || (!(bb & gap))))
            inside_block = 0;
        else if (((ab & gap) || (bb & gap)) && ((ab != gap) || (bb != gap)))
            inside_block = 1;
        else
            inside_block = 0;
        if (((gap & ab) || (gap & bb)) && (!(sb & gap)) && !extending_gap) {
            prev_block = inside_block;
            extending_gap = 1;
        }
        else if ((gap & ab) && (gap & bb) && (sb & gap) && (sb != gap) &&
                extending_gap && inside_block && !prev_block) {
            sb = (~gap) & sb;
            prev_block = 0;
        }
        else if ((gap & ab) && (gap & bb) && (1 == extending_gap)) {
            prev_block = inside_block;
            extending_gap = 0;
        }

        seq_set (s, i, sb);
    }
    algn_remove_gaps (gap, s);
    return;
}

inline void
algn_ancestor_2 (seq_p seq1, seq_p seq2, cost_matrices_2d_p m, seq_p sm ) {
    SEQT *begin1, *begin2;
    int interm;
    int i, gap, is_combinations, cost_model;
    begin1 = seq_get_begin (seq1);
    begin2 = seq_get_begin (seq2);
    gap = cm_get_gap_2d (m);
    is_combinations = m->combinations;
    cost_model = m->cost_model_type;
    for (i = seq_get_len (seq1) - 1; i >= 0; i--) {
        interm = cm_get_median (m, begin1[i], begin2[i]);
        if ((!is_combinations) || (1 != cost_model)) {
            if (interm != gap) seq_prepend (sm, interm);
        }
        else seq_prepend (sm, interm);
    }
    if ((!is_combinations) || ((1 != cost_model) && (gap != seq_get_element (sm, 0))))
        seq_prepend (sm, gap);
    else if (is_combinations)
        algn_correct_blocks_affine (gap, sm, seq1, seq2);
    return;
}



/*
 * Given three aligned sequences seq1, seq2, and seq3, the median between them is
 * returned in the sequence sm, using the cost matrix stored in m.
 */
inline void
algn_get_median_3d (seq_p seq1, seq_p seq2, seq_p seq3, 
                    cost_matrices_3d_p m, seq_p sm) {
    SEQT *end1, *end2, *end3;
    int interm;
    int i;
    end1 = seq_get_end (seq1);
    end2 = seq_get_end (seq2);
    end3 = seq_get_end (seq3);
    for (i = seq_get_len (seq1) - 1; i >= 0; i--) {
        interm = cm_get_median_3d (m, *end1, *end2, *end3);
        seq_prepend (sm, interm);
    }
    return;
}

void
algn_union (seq_p seq1, seq_p seq2, seq_p su) {
    assert (seq_get_len (seq1) == seq_get_len (seq2));
    assert (seq_get_cap (seq1) >= seq_get_len (seq2));
    int len, i;
    len = seq_get_len (seq1);
    for (i = len - 1; i >= 0; i--)
        seq_prepend (su, (seq_get_element (seq1, i) | seq_get_element (seq2, i)));
    return;
}

/*
value
algn_CAML_union (value seq1, value seq2, value su) {
    CAMLparam3(seq1, seq2, su);
    seq_p sseq1, sseq2, ssu;
    Seq_custom_val(sseq1, seq1);
    Seq_custom_val(sseq2, seq2);
    Seq_custom_val(ssu, su);
    algn_union (sseq1, sseq2, ssu);
    CAMLreturn(Val_unit);
}

value
algn_CAML_median_2_no_gaps (value seq1, value seq2, value m, value sm) {
    CAMLparam4(seq1, seq2, m, sm);
    seq_p sseq1, sseq2, ssm;
    cost_matrices_2d_p tm;
    Seq_custom_val(sseq1, seq1);
    Seq_custom_val(sseq2, seq2);
    Seq_custom_val(ssm, sm);
    tm = Cost_matrix_struct(m);
    algn_get_median_2d_no_gaps (sseq1, sseq2, tm, ssm);
    CAMLreturn(Val_unit);
}

value
algn_CAML_median_2_with_gaps (value seq1, value seq2, value m, value sm) {
    CAMLparam4(seq1, seq2, m, sm);
    seq_p sseq1, sseq2, ssm;
    cost_matrices_2d_p tm;
    Seq_custom_val(sseq1, seq1);
    Seq_custom_val(sseq2, seq2);
    Seq_custom_val(ssm, sm);
    tm = Cost_matrix_struct(m);
    algn_get_median_2d_with_gaps (sseq1, sseq2, tm, ssm);
    CAMLreturn(Val_unit);
}

value
algn_CAML_median_3 (value seq1, value seq2, value seq3, value m, value sm) {
    CAMLparam5(seq1, seq2, seq3, m, sm);
    seq_p sseq1, sseq2, sseq3, ssm;
    cost_matrices_3d_p tm;
    Seq_custom_val(sseq1, seq1);
    Seq_custom_val(sseq2, seq2);
    Seq_custom_val(sseq3, seq3);
    Seq_custom_val(ssm, sm);
    tm = Cost_matrix_struct_3d(m);
    algn_get_median_3d (sseq1, sseq2, sseq3, tm, ssm);
    CAMLreturn(Val_unit);
}
*/

/* Alignment following the algorithm of Myers , 1986. */
static zarrt v = NULL;

int
algn_myers (zarrt v, seq_p a, seq_p b, int max) {
    int d, kp1, km1, la, lb, k, x, y;
    la = seq_get_len (a) - 1;
    lb = seq_get_len (b) - 1;
    if (zarr_clear (v, max)) {
        for (d = 0; d <= max; d++) {
            for (k = -d; k <= d; k+=2) {
                zarr_get (v, k + 1, &kp1);
                zarr_get (v, k - 1, &km1);
                if ((k == -d) || ((k != d) && (km1 < kp1))) x = kp1;
                else x = km1 + 1;
                y = x - k;

                while ((x < la) && (y < lb) &&
                        (seq_get_element (a, x + 1) == seq_get_element (b, y + 1))) {
                    x++;
                    y++;
                }
                zarr_set (v, k, x);
                if ((x >= la) && (y >= lb)) return d;
            }
        }
    }
    return -1;
}

/*
value
algn_CAML_myers (value sa, value sb) {
    CAMLparam0();
    seq_p a, b;
    int res, max;
    Seq_custom_val(a, sa);
    Seq_custom_val(b, sb);
    max = seq_get_len (a) + seq_get_len (b);
    if (max > zarr_length (v)) {
        if ((v != NULL) && (zarr_realloc (v, max))) {
            printf("Allocation error.\n");
            exit(1);
            // failwith ("Allocation error.");
        } else {
            v = zarr_alloc (max);
            if (v == NULL) {
                printf("Allocation error\n");
                exit(1);
                // failwith ("Allocation error.");
            }
        }
    }
    res = algn_myers (v, a, b, max);
    CAMLreturn (Val_int (res));
}

value
algn_CAML_ancestor_2 (value sa, value sb, value cm, value sab) {
    CAMLparam4(sa, sb, cm, sab);
    seq_p a, b, ab;
    cost_matrices_2d_p tm;

    Seq_custom_val(a, sa);
    Seq_custom_val(b, sb);
    Seq_custom_val(ab, sab);
    tm = Cost_matrix_struct(cm);
    algn_ancestor_2 (a, b, tm, ab);
    CAMLreturn (Val_unit);
}

void
algn_copy_backtrace (int seq1, int seq2, const nw_matrices_p m, value res) {
    value row;
    int i, j;
    DIRECTION_MATRIX *d;
    d = mat_get_2d_direct (m);
    for (i = 0; i < seq1; i++) {
        row = Field(res, i);
        for (j = 0; j < seq2; j++) {
            Store_field(row, j, Val_int (*(d + j)));
        }
        d += j;
    }
    return;
}

value
algn_CAML_create_backtrack (value lsa, value lsb, value scm, value sres) {
    CAMLparam4(lsa, lsb, scm, sres);
    int la, lb;
    nw_matrices_p m;

    la = Int_val(lsa);
    lb = Int_val(lsb);
    m = Matrices_struct(scm);
    algn_copy_backtrace (la, lb, m, sres);
    CAMLreturn(Val_unit);
}
*/
#include "union.c"