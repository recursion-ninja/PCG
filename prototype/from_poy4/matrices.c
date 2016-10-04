/* POY 4.0 Beta. A phylogenetic analysis program using Dynamic Homologies.    */
/* Copyright (C) 2007  Andr�s Var�n, Le Sy Vinh, Illya Bomash, Ward Wheeler,  */
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

#include <stdio.h>
#include <stdlib.h>

#include "debug.h"
#include "matrices.h"
// #include "cm.h"


/* 
 * For memory management efficiency, I will keep all the matrices in one big
 * chunk of memory, that I can reallocate as a whole, and reduce fragmentation
 * a lot if possible, all the alignment calculations and all the matrices that
 * are precomputed to speedup the alignments are held here.
 */
inline int
mat_size_of_3d_matrix (int w, int d, int h, int k) {
    /* Not sure what this was for, but kept for posterity's sake
       int basic_cube;
       int prism_1, prism_2, pyramid;
       basic_cube = k * k * k;
       prism_1 = (d - k) * (d - k) * k;
       prism_2 = (w - k) * (w - k) * k;
       pyramid = (w - k) * (w - k + 1) * (2 * (w - k) + 1) / 6;
       if (h > 2 * k) basic_cube += (h - (2 * k)) * w * d;
       return (basic_cube + prism_2 + prism_1 + pyramid);
    */
    return (w * d * h);
}

void print_matrices(nw_matrices_p m, int alphSize) {
    printf("\nMatrices:\n");
    printf("    NW Matrix len:         %d\n", m->len);
    printf("    Efficiency mtx len:    %d\n", m->len_eff);
    printf("    Precalc mtx len:       %d\n", m->len_pre);

    printf("\n    Precalculated nw matrix:\n");
    for( size_t i = 0; i < m->len_pre; i += alphSize) {
        printf("    ");
        for( size_t j = 0; j < alphSize; j++) {
            printf("%4d", m->precalc[i + j]);
        }
        printf("\n"); 
    }
    
}

// TODO: wtf is with the 12 here?
inline int
mat_size_of_2d_matrix (int w, int h) {
    if (w > h) return (w * 12);
    else return (h * 12);
}

void
mat_clean_direction_matrix (nw_matrices_p m) {
    int len = m->len;
    int i;
    for (i = 0; i < len; i++) 
        m->dir_mtx_2d[i] = (DIRECTION_MATRIX) 0;
    return;
}

/** Allocate or reallocate space for the six matrices, for both 2d and 3d alignments.
 *  @param lcm is length of original alphabet including gap.
 *  Checks current allocation size and increases size if 
 */
inline void
mat_setup_size (nw_matrices_p m, int len_seq1, int len_seq2, int len_seq3, int is_ukk, int lcm) {
    if(DEBUG_MAT) {
        printf("\n---mat_setup_size\n");
    }
    int len, len_2d, len_precalc, len_dir;
    if (len_seq3 == 0) {           /* If the size setup is only for 2d */
        len         = mat_size_of_2d_matrix (len_seq1, len_seq2);
        len_precalc = (1 << lcm) * len_seq1;
        len_dir     = (len_seq1 + 1) * (len_seq2 + 1);
        len_2d      = 0;
    } else {                       /* If the size setup is for 3d */
        len         = mat_size_of_3d_matrix (len_seq1, len_seq2, len_seq3, is_ukk);
        len_precalc = (1 << lcm) * (1 << lcm) * len_seq2;  // TODO: why sequence 2?
        len_2d      = len_seq1 * len_seq2;
        len_dir     = len_2d * len_seq3;
    }
    if (DEBUG_MAT) {
        printf("len_eff: %d, \nlen: %d\n", m->len_eff, len);
    }
    if (m->len_eff < len) {         /* If the current 2d or 3d matrix is not large enough */
        if (DEBUG_MAT) {
            printf("len_eff too small. New allocation: %d\n", len);
        }
        m->cube    = m->nw_costMtx = realloc (m->nw_costMtx, (len * sizeof(int)));
        m->len_eff = len;
    }
    if (m->len < len_dir) {         /* If the other matrices are not large enough */
        if (DEBUG_MAT) {
            printf("len nw cost mtx too small. New allocation: %d\n", len_dir);
        }
        m->cube_d = m->dir_mtx_2d = 
            realloc (m->dir_mtx_2d, len_dir * sizeof(DIRECTION_MATRIX) );
        if (0 != len_2d) {
            if (DEBUG_MAT) {
                printf("\n3d alignment. len_2d: %d\n", len_2d);
            }
            m->pointers_3d = realloc (m->pointers_3d, len_2d * sizeof(int));
            if (m->pointers_3d == NULL) {
                printf("Memory allocation problem in pointers 3d.\n");
                exit(1);
                // failwith ("Memory allocation problem in pointers 3d.");
            }
        }
        m->len = len_dir;
    }
    if (m->len_pre < len_precalc) {
        if (DEBUG_MAT) {
            printf("precalc matrix too small. New allocation: %d\n", len_precalc);
        }
        m->precalc = realloc (m->precalc, len_precalc * sizeof(int));
        m->len_pre = len_precalc;
    }
    /* Check if there is an allocation error then abort program */
    if ((len > 0) && (m->cube == NULL)) {
        printf("Memory allocation problem in cube.\n");
        exit(1);
        // failwith ("Memory allocation problem in cube.");
    }
    if ((len_dir > 0) && (m->dir_mtx_2d == NULL)) {
        printf("Memory allocation problem in dir_mtx_2d\n");
        exit(1);
        // failwith ("Memory allocation problem in dir_mtx_2d");
    }
    if ((len_precalc > 0) && (m->precalc == NULL)) {
        printf("Memory allocation problem in precalc\n");
        exit(1);
        // failwith ("Memory allocation problem in precalc");
    }
    if (DEBUG_MAT) {
        printf("\nFinal allocated size of matrices:\n" );
        printf("    efficiency: %d\n", m->len_eff);
        printf("    nw matrix:  %d\n", m->len);
        printf("    precalc:    %d\n", m->len_pre);
    }
}

int *
mat_get_2d_prec (const nw_matrices_p m) {
    return (m->precalc);
}

int *
mat_get_3d_prec (const nw_matrices_p m) {
    return (m->precalc);
}

int *
mat_get_2d_nwMtx (nw_matrices_p m) {
    return (m->nw_costMtx);
}

DIRECTION_MATRIX *
mat_get_2d_direct (const nw_matrices_p m) {
    return (m->dir_mtx_2d);
}

// TODO: I think this can be removed, which means pointers_3d can be, also.
int **
mat_get_3d_pointers (nw_matrices_p m) {
    return (m->pointers_3d);
}

int *
mat_get_3d_matrix (nw_matrices_p m) {
    return (m->cube);
}

DIRECTION_MATRIX *
mat_get_3d_direct (nw_matrices_p m) {
    return (m->cube_d);
}



void
mat_print_algn_2d (nw_matrices_p m, int w, int h) {
    int *mm;
    int i, j;
    mm = mat_get_2d_nwMtx (m);
    for (i = 0; i < h; i++) {
        for (j = 0; j < w; j++)
            fprintf (stdout, "%d\t", *(mm + (w * i) + j));
        fprintf (stdout, "\n");
    }
    fprintf (stdout, "\n");
    return;
}


void
mat_print_algn_3d (nw_matrices_p m, int w, int h, int d) {
    int *mm;
    int i, j, k, pos;
    mm = mat_get_3d_matrix (m);
    for (i = 0; i < h; i++) {
        for (j = 0; j < d; j++) {
            for (k = 0; k < w; k++) {
                pos = (i * d * w) + (d * j) + k;
                fprintf (stdout, "%d\t", *(mm +pos));
            }
            fprintf (stdout, "\n");
        }
        fprintf (stdout, "\n");
    }
    fprintf (stdout, "\n");
    return;
}