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

/* A cost matrix library                                                      */

#ifndef CM_H

//#define DEBUG 0
#define CM_H 1
#define Cost_matrix_struct(a) ((struct cost_matrices_2d *) Data_custom_val(a))
#define Cost_matrix_struct_3d(a) ((struct cost_matrices_3d *) Data_custom_val(a))
#include "debug.h"
#include "matrices.h"
#include "seq.h"

/*
 * Check cost_matrices_3d for further information. This is the corresponding data
 * structure for two dimensional sequence alignment. 
 */
struct cost_matrices_2d {
    int alphSize;        // alphabet size, including ambiguities if combinations == True
    int lcm;             // ceiling of log_2 (alphSize)
    int gap;             // gap value (1 << alphSize + 1)
    int cost_model_type; /* The type of cost model to be used in the alignment, 
                          * i.e. affine or not. 
                          * Based on cost_matrix.ml, values are:
                          * � linear == 0 
                          * � affine == 1
                          * � no_alignment == 2
                          */
    int combinations;    /* This is a flag set to true if we are going to accept
                          * all possible combinations of the elements in the alphabet
                          * in the alignments. This is not true for protein sequences 
                          * for example, where the number of elements of the alphabet 
                          * is already too big to build all the possible combinations.
                          */
    int gap_open;        /* The cost of opening a gap. This is only useful in 
                          * certain cost_model_types. 
                          */
    int is_metric;       /* if tcm is symmetric
                          * Not present in 3d. */
    int all_elements;    // total number of elements TODO: figure out how this is different from alphSize
    int *cost;           /* The transformation cost matrix, including ambiguities, 
                          * storing the **best** cost for each ambiguity pair
                          */
    SEQT *median;        /* The matrix of possible medians between elements in the 
                          * alphabet. The best possible medians according to the cost 
                          * matrix. 
                          */
    int *worst;          /* The transformation cost matrix, including ambiguities, 
                          * storing the **worst** cost for each ambiguity pair
                          * Missing in 3d
                          */
    int *prepend_cost;   /* The cost of going from gap -> each base. For ambiguities, use best cost.
                          * Set up as all_elements x all_elements
                          * matrix, but seemingly only first row is used. 
                          * Missing in 3d 
                          */
    int *tail_cost;      /* As prepend_cost, but with reverse directionality, so base -> gap. 
                          * As with prepend_cost, seems to be allocated as too large. 
                          * Missing in 3d 
                          */
};

/*
 * A pointer to the cost_matrices_2d structure.
 */
typedef struct cost_matrices_2d * cost_matrices_2d_p;

/** A three dimesional cost matrix 
 *
 * For three way sequence alignment, this structure holds the cost of
 * transforming the elements of an alphabet.  A cost matrix can only be applied
 * on a particular alphabet.
 */
struct cost_matrices_3d {
    int alphSize;           /** The number of elements in the alphabet */
    int lcm;                /** The logarithm base 2 of alphSize */
    int gap;                /** The integer representing a gap in the alphabet */
    int cost_model_type;    /** The type of cost model to be used in the alignment */
    int combinations;       /** This is a flag set to true if we are going to accept
                                all possible combinations of the elements in the alphabet
                                in the alignments. This is not true for protein sequences 
                                for example, where the number of elements of the alphabet 
                                is already too big to build all the possible combinations.
                             */
    int gap_open;           /** The cost of opening a gap. This is only useful in 
                                certain cost_model_type's. */
    int all_elements;       /** The integer that represents all the combinations, used 
                                for ambiguities */
    int *cost;              /** The transformation cost matrix. The ordering is row-major,
                             *  and the lookup is a->b, where a is a row label and b is 
                             *  a column label
                             */
    SEQT *median;           /** The matrix of possible medians between elements in the 
                                alphabet. The best possible medians according to the cost 
                                matrix. */
};

/* 
 * A pointer to a three dimensional cost matrix 
 */ 
typedef struct cost_matrices_3d * cost_matrices_3d_p;

void cm_print (cost_matrices_2d_p c);

void cm_print_matrix (int* m, int w, int h);

/* 
 * Creates a cost matrix with memory allocated for an alphabet of size alphSize
 * (not including the gap representation which is internally chosen), and whose
 * size must consider all possible combinations of characters in the alphabeet
 * iff combinations != 0. Set the affine gap model paramters to the values
 * stored in do_aff, gap_open, in the cost matrix res. 
 * In case of error the function fails with the message "Memory error.".
 */
void cm_alloc_set_costs_2d (int alphSize, int combinations, int do_aff, int gap_open, \
        int is_metric, int all_elements, cost_matrices_2d_p res);


void
cm_set_cost_2d (int a, int b, int v, cost_matrices_2d_p c);

void
cm_set_cost_3d (int a, int b, int cp, int v, cost_matrices_3d_p c);

/* 
 * Retrieves the alphabet size flag from the transformation cost matrix.
 */
inline int 
cm_get_alphabet_size (cost_matrices_2d_p c);

/*
 * Retrieves the gap code as defined in the transformation cost matrix. 
 */
SEQT
cm_get_gap_2d (const cost_matrices_2d_p c);

SEQT
cm_get_gap_3d (const cost_matrices_3d_p c);

/*
 * Retrieves a pointer to the memory position stored in the precalculated array
 * of costs for the alphabet in three dimensions, vs. a sequence s3. This is
 * used in the 3d alignments procedures for vectorization. to is a pointer to
 * the precalculated cube, s3l is the length of the sequence included in the
 * precalculated cube, alphSize is the lcm of the alphabet of the sequence, s1c is
 * the character from s1, and s2c is defined in an analogous manner. s3p is the
 * position in the sequence s3 of interest. s3p should be less than s3l.
 */
static inline int *
cm_get_pos_in_precalc (const int *toOutput, int s3l, int alphSize, int s1c, int s2c, int s3p);

/* 
 * During the 3d alignments, calculations are performed for each element in the
 * array using the complete vectors of the precalculated matrix. This function
 * retrieves the first element in those precalculated arrays. The parameters
 * definitions are analogous to those explained in cm_get_pos_in_precalc 
 */
int *
cm_get_row_precalc_3d (const int *toOutput, int s3l, int alphSize, int s1c, int s2c);

/*
 * Retrieves the affine flag from the transformation cost matrix. Remember this
 * flag is 1 if true, otherwise 0. 
 */
int
cm_get_affine_flag (cost_matrices_2d_p c);

/*
 * Gets the total number of possible combinations of an alphabeet of size
 * alphSize. The size of the alphabet must be bigger than 0.
 */
static inline int 
cm_combinations_of_alphabet (const int alphSize);

/*
 * Calculates the median position in a transformation cost matrix for an
 * alphabet of size alphSize and elements a and b.
 */
static inline int
cm_calc_median_position (SEQT a, SEQT b, int alphSize);

/*
 * The median between to elements in the alphabet hold by t.
 * @param t is a transformation cost matrix
 * @param a is an element in the alphabet of t
 * @param b is an element in the alphabet of t
 * @return an element in the alphabet of t which is a median between a and b
 * according to the transformation cost matrix hold in t.
 */
SEQT
cm_get_median (const cost_matrices_2d_p t, SEQT a, SEQT b);

/*
 * Retrieves the transformation cost of the elements a and b as stored in the
 * transformation cost matrix tcm, containing information for an alphabet of
 * size alphSize. 
 */
int
cm_calc_cost (int *tcm, SEQT a, SEQT b, int alphSize);

/* 
 * The transformation cost matrix, as stored in ocaml, may have the actual
 * matrices located at certain offset from the start of the matrix. This
 * function retrieves the actual starting position.
 */
static inline int *
cm_get_transformation_cost_matrix (const cost_matrices_2d_p a);

int
cm_get_lcm (cost_matrices_2d_p c);

int *
cm_get_tail_cost (const cost_matrices_2d_p a);

static inline int *
cm_get_prepend_cost (const cost_matrices_2d_p a);

/*
 * Gets the row in the transformation cost matrix tcm where the transformations
 * of character a are located, when tcm holds information for an alphabet of
 * size alphSize.
 */
static inline int *
cm_get_row (int *tcm, SEQT a, int alphSize);

/* set the value of c->worst at location (a,b) to v */
void
cm_set_worst (int a, int b, int v, cost_matrices_2d_p c);

/* 
 * Fills a precalculated matrix with the cost of comparing each elment in the
 * sequence s with each element in the alphabet specified in the transformation
 * cost matrix costMtx. 
 *
 * @param costMtx is the transformation cost matrix to calculate the precalculated
 *  vectors.
 * @param toOutput is the matrix that will hold the output. 
 * @param s is the sequence for which the cost matrix will be precalculated.
 *
 * This function is only valid for two dimensional alignments.
 * TODO: why is this in cm instead of matrices?
 */
void
cm_precalc_4algn (const cost_matrices_2d_p costMtx, nw_matrices_p toOutput, const seq_p s);

/* 
 * Gets the precalculated row for a particular character in the alphabet.
 * @param p is the precalculated matrix.
 * @param item is the element in the alphabet that produced p that should be
 *  generated.
 * @param len is the length of the sequence that was source of the precalculated
 *  matrix.
 */
const int *
cm_get_precal_row (const int *p, SEQT item, int len);



/** As with 2d, but doesn't compute worst, prepend or tail */
void
cm_alloc_set_costs_3d (int alphSize, int combinations, int do_aff, int gap_open, 
                       int all_elements, cost_matrices_3d_p res);

/* 
 * The median between three alphabet elements a, b and c.
 * @param t is the transformation cost matrix
 * @param a is the first element in the alphabet
 * @param b is the second element in the alphabet
 * @param c is the third element in the alphabet
 * @return an element of the alphabet contained in t that provides the best
 * median between a, b, and c, according to the transformation cost matrix
 * contained in t.
 */
SEQT
cm_get_median_3d (const cost_matrices_3d_p t, SEQT a, SEQT b, SEQT c);

inline int
cm_get_alphabet_size_3d (cost_matrices_3d_p c);

/*
 * Retrieves the gap code as defined in the transformation cost matrix. 
 */
SEQT
cm_get_gap_3d (const cost_matrices_3d_p c);

/*
 * Retrieves the affine flag from the transformation cost matrix. Remember this
 * flag is 1 if true, otherwise 0. 
 */
int
cm_get_affine_flag_3d (cost_matrices_3d_p c);

/*
 * Retrieves the gap opening cost under affine gap cost model. If affine gap
 * cost model is false, the retrieved value could make no sense at all.
 */
int
cm_get_gap_opening_parameter_3d (const cost_matrices_3d_p c);

/*
 * Retrieves the gap opening cost under affine gap cost model. If affine gap
 * cost model is false, the retrieved value could make no sense at all.
 */
inline int
cm_get_gap_opening_parameter_3d (const cost_matrices_3d_p c);

/*
 * Gets the row in the transformation cost matrix tcm where the transformations
 * of character a are located, when tcm holds information for an alphabet of
 * size alphSize.
 */
static inline int *
cm_get_row_3d (int *tcm, SEQT a, SEQT b, int alphSize);

/*
 * Fills a three-dimensional precalculation alignment matrix for sequence s 
 * See cm_precalc_4algn for further information. This is the
 * corresponding function for three dimensional alignments.
 * TODO: Why is this here, and not in matrices.c?
 */
void
cm_precalc_4algn_3d (const cost_matrices_3d_p c, int *toOutput, const seq_p s);

/*
 * Deallocates the memory structure iff there are no more pointers to it,
 * otherwise it will just decrease the garbage collection counter. 
 */
inline void
cm_free (cost_matrices_2d_p c);

int
cm_get_gap_opening_parameter (cost_matrices_2d_p c);

int
cm_get_cost (int a, int b, cost_matrices_2d_p c);

int
cm_get_value (int a, int b, int *p, int alphSize);

void
cm_set_prepend_2d (int a, int b, cost_matrices_2d_p c);

void
cm_set_tail_2d (int a, int b, cost_matrices_2d_p c);

void
cm_set_median_2d (SEQT a, SEQT b, SEQT v, cost_matrices_2d_p c);

void
cm_set_median_3d (SEQT a, SEQT b, SEQT cp, SEQT v, cost_matrices_3d_p c);

void
cm_print_median (SEQT* m, int w, int h);


#endif /* CM_H */

