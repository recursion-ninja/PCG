#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "alignCharacters.h"
#include "c_alignment_interface.h"
#include "c_code_alloc_setup.h"
#include "debug_constants.h"
// #include "costMatrix.h"
#include "alignmentMatrices.h"
#include "ukkCheckPoint.h"
#include "ukkCommon.h"


int align2d( alignIO_t          *inputChar1_aio
           , alignIO_t          *inputChar2_aio
           , alignIO_t          *gappedOutput_aio
           , alignIO_t          *ungappedOutput_aio
           // , alignIO_t          *unionOutput_aio
           , cost_matrices_2d_t *costMtx2d
           , int                 getUngapped
           , int                 getGapped
           , int                 getUnion
           )
{

    if (DEBUG_ALGN) {
        printf("\n\nalign2d char1 input:\n");
        printf("\ninput char 1:");
        alignIO_print(inputChar1_aio);
        printf("input char 2:");
        alignIO_print(inputChar2_aio);
    }

    const size_t CHAR_CAPACITY = inputChar1_aio->length + inputChar2_aio->length + 2; // 2 to account for gaps,
                                                                                      // which will be added in initializeChar()

    alignIO_t *longIO,
              *shortIO;

    dyn_character_t *longChar     = malloc(sizeof(dyn_character_t)); // input to algn_nw_2d
    dyn_character_t *shortChar    = malloc(sizeof(dyn_character_t)); // input to algn_nw_2d
    dyn_character_t *retShortChar = malloc(sizeof(dyn_character_t)); // aligned character outputs from backtrace (not medians)
    dyn_character_t *retLongChar  = malloc(sizeof(dyn_character_t)); // aligned character outputs from backtrace (not medians)

    /*** Most character allocation is now done on Haskell side, but these two are local. ***/
    /*** longChar and shortChar will both have pointers into the input characters, so don't need to be initialized separately ***/
    initializeChar(retLongChar,  CHAR_CAPACITY);
    initializeChar(retShortChar, CHAR_CAPACITY);

    // NOTE: We do not set the swapped flag, regardless of whether we swap the inputs.
    //       Doing so causes the C algorithm to return inconsistent reult inputs
    //       which create an NW matrix that contains a cell with equally costly
    //       left-arrow (INSERT) and up-arrow (DELETE) directions but a more
    //       costly diagonal-arrow (ALIGN) direction. This is because internally
    //       the algn_backtrace_2d function will check the 'swapped' flag and
    //       conditionally change the bias preference between left-arrow (INSERT)
    //       and up-arrow (DELETE) directions. For our use of the C code, we do
    //       not require this conditional biasing. We handle all swapping in this
    //       C interface.
    //
    //       TODO: I believe that the swapped flag is superfluous for our interface and
    //       the swapped != 0 code branches in algn_backtrace_2d is all dead code.
    const int swapped = 0;

    // size_t alphabetSize = costMtx2d->alphSize;
    size_t alphabetSize = costMtx2d->costMatrixDimension;

    if (inputChar1_aio->length >= inputChar2_aio->length) {
        alignIOtoDynChar(longChar, inputChar1_aio, alphabetSize);
        longIO = inputChar1_aio;

        alignIOtoDynChar(shortChar, inputChar2_aio, alphabetSize);
        shortIO = inputChar2_aio;

    } else {
        alignIOtoDynChar(longChar, inputChar2_aio, alphabetSize);
        longIO = inputChar2_aio;

        alignIOtoDynChar(shortChar, inputChar1_aio, alphabetSize);
        shortIO = inputChar1_aio;
    }

    if (DEBUG_ALGN) {
        printf("\nafter copying, char 1:\n");
        dyn_char_print(longChar);
        printf("\nafter copying, char 2:\n");
        dyn_char_print(shortChar);
    }
    //printf("Before NW init.\n");
    //fflush(stdout);
    alignment_matrices_t *algnMtxs2d = malloc( sizeof(alignment_matrices_t) );
    initializeAlignmentMtx(algnMtxs2d, longChar->len, shortChar->len, costMtx2d->costMatrixDimension);
    //printf("After  NW init.\n");
    //fflush(stdout);

    // deltawh is for use in Ukonnen, it gives the current necessary width of the Ukk matrix.
    // The following calculation to compute deltawh, which increases the matrix height or width in algn_nw_2d,
    // was pulled from POY ML code.
    int deltawh     = 0;
    int diff        = longChar->len - shortChar->len;
    int lower_limit = .1 * longChar->len;

    if (deltawh) {
        deltawh = diff < lower_limit ? lower_limit : deltawh;
    } else {
        deltawh = diff < lower_limit ? lower_limit / 2 : 2;
    }

    //printf("%d, %zu, %d, %zu\n", shortCharLen, shortChar->len, longCharLen, longChar->len);
    //printf("Before align cost.\n");
    //fflush(stdout);
    int algnCost = algn_nw_2d( shortChar, longChar, costMtx2d, algnMtxs2d, deltawh );

    //printf("After align cost.\n");
    //fflush(stdout);
    if (getGapped || getUngapped || getUnion) {
        //printf("Before backtrace.\n"), fflush(stdout);
        algn_backtrace_2d (shortChar, longChar, retShortChar, retLongChar, algnMtxs2d, costMtx2d, 0, 0, swapped);
        // printf("After  backtrace.\n"), fflush(stdout);
        // dyn_char_print(retShortChar);
        // dyn_char_print(retLongChar);

        if (getUngapped) {
            dyn_character_t *ungappedMedianChar = malloc(sizeof(dyn_character_t));
            initializeChar(ungappedMedianChar, CHAR_CAPACITY);

            algn_get_median_2d_no_gaps (retShortChar, retLongChar, costMtx2d, ungappedMedianChar);
            // printf("\n\nUngapped median:\n"), fflush(stdout);
            // dyn_char_print(ungappedMedianChar);

            dynCharToAlignIO(ungappedOutput_aio, ungappedMedianChar);
            // printf("\n\nUngapped median copy:\n"), fflush(stdout);
            // alignIO_print(ungappedOutput_aio);

            freeChar(ungappedMedianChar);


            dynCharToAlignIO(longIO,  retLongChar);
            dynCharToAlignIO(shortIO, retShortChar);

            // printf("\nAfter copy.\n"), fflush(stdout);
            // alignIO_print(longIO);
            // alignIO_print(shortIO);

        }
        if (getGapped && !getUnion) {
        //printf("In here!\n"), fflush(stdout);
            dyn_character_t *gappedMedianChar   = malloc(sizeof(dyn_character_t));

        //printf("Before initialize character!\n"), fflush(stdout);
            initializeChar(gappedMedianChar, CHAR_CAPACITY);
        //printf("After  initialize character!\n"), fflush(stdout);

        //printf("Before algn_get_median\n"), fflush(stdout);
            algn_get_median_2d_with_gaps (retShortChar, retLongChar, costMtx2d, gappedMedianChar);
        //printf("After  algn_get_median\n"), fflush(stdout);

        //printf("Before dynCharToAlignIO\n"), fflush(stdout);
            dynCharToAlignIO(gappedOutput_aio, gappedMedianChar);
        //printf("After  dynCharToAlignIO\n"),  fflush(stdout);

            freeChar(gappedMedianChar);

            dynCharToAlignIO(longIO,  retLongChar);
            dynCharToAlignIO(shortIO, retShortChar);

        }
        if (getUnion) {
            dyn_character_t *gappedMedianChar = malloc(sizeof(dyn_character_t));

            initializeChar(gappedMedianChar, CHAR_CAPACITY);

            algn_union (retShortChar, retLongChar, gappedMedianChar);

            dynCharToAlignIO(gappedOutput_aio, gappedMedianChar);

            freeChar(gappedMedianChar);

            /*** following once union has its own output field again ***/
            // dyn_character_t *unionChar = malloc(sizeof(dyn_character_t));
            // initializeChar(unionChar, CHAR_CAPACITY);
            // algn_union(retShortChar, retLongChar, gappedMedianChar);

            // dynCharToAlignIO(unionChar, unionOutputChar);
            // freeChar(unionChar);

            dynCharToAlignIO(longIO,  retLongChar);
            dynCharToAlignIO(shortIO, retShortChar);
        }
    }


    //freeCostMtx(costMtx2d, 1);  // 1 is 2d
    freeNWMtx(algnMtxs2d);

    freeChar(retLongChar);
    freeChar(retShortChar);

    return algnCost;

}


int align2dAffine( alignIO_t          *inputChar1_aio
                 , alignIO_t          *inputChar2_aio
                 , alignIO_t          *gappedOutput_aio
                 , alignIO_t          *ungappedOutput_aio
                 // , alignIO_t          *unionOutput_aio
                 , cost_matrices_2d_t *costMtx2d_affine
                 , int                 getMedians
                 )
{

    if (DEBUG_ALGN) {
        printf("\n\nalign2d char1 input:\n");
        printf("\ninput char 1:");
        alignIO_print(inputChar1_aio);
        printf("input char 2:");
        alignIO_print(inputChar2_aio);
    }

    const size_t CHAR_CAPACITY = inputChar1_aio->length + inputChar2_aio->length + 2; // 2 to account for gaps,
                                                                                      // which will be added in initializeChar()
    // printf("capacity%zu\n", CHAR_CAPACITY);
    alignIO_t *longIO,
              *shortIO;


    dyn_character_t *longChar     = malloc(sizeof(dyn_character_t)); // input to algn_nw_2d
    dyn_character_t *shortChar    = malloc(sizeof(dyn_character_t)); // input to algn_nw_2d
    dyn_character_t *retShortChar = malloc(sizeof(dyn_character_t)); // aligned character outputs from backtrace (not medians)
    dyn_character_t *retLongChar  = malloc(sizeof(dyn_character_t)); // aligned character outputs from backtrace (not medians)

    /*** Most character allocation is now done on Haskell side, but these two are local. ***/
    /*** longChar and shortChar will both have pointers into the input characters, so don't need to be initialized separately ***/
    initializeChar(retLongChar,  CHAR_CAPACITY);
    initializeChar(retShortChar, CHAR_CAPACITY);

    // NOTE: We do not set the swapped flag, regardless of whether we swap the inputs.
    //       Doing so causes the C algorithm to return inconsistent reult inputs
    //       which create an NW matrix that contains a cell with equally costly
    //       left-arrow (INSERT) and up-arrow (DELETE) directions but a more
    //       costly diagonal-arrow (ALIGN) direction. This is because internally
    //       the algn_backtrace_2d function will check the 'swapped' flag and
    //       conditionally change the bias preference between left-arrow (INSERT)
    //       and up-arrow (DELETE) directions. For our use of the C code, we do
    //       not require this conditional biasing. We handle all swapping in this
    //       C interface.
    //
    //       TODO: I believe that the swapped flag is superfluous for our interface and
    //       the swapped != 0 code branches in algn_backtrace_2d is all dead code.
    // const int swapped = 0;

    size_t alphabetSize = costMtx2d_affine->costMatrixDimension;

    if (inputChar1_aio->length >= inputChar2_aio->length) {
        alignIOtoDynChar(longChar, inputChar1_aio, alphabetSize);
        longIO = inputChar1_aio;

        alignIOtoDynChar(shortChar, inputChar2_aio, alphabetSize);
        shortIO = inputChar2_aio;

    } else {
        alignIOtoDynChar(longChar, inputChar2_aio, alphabetSize);
        longIO = inputChar2_aio;

        alignIOtoDynChar(shortChar, inputChar1_aio, alphabetSize);
        shortIO = inputChar1_aio;
    }

    if (DEBUG_ALGN) {
        printf("\nafter copying, char 1:\n");
        dyn_char_print(longChar);
        printf("\nafter copying, char 2:\n");
        dyn_char_print(shortChar);
    }

    // TODO: document these variables
    // int *matrix;                        //
    unsigned int *close_block_diagonal;       //
    unsigned int *extend_block_diagonal;      //
    unsigned int *extend_vertical;            //
    unsigned int *extend_horizontal;          //
    unsigned int *final_cost_matrix;          //
    unsigned int *precalcMtx;                 //
    unsigned int *matrix_2d;                  //
    unsigned int *precalc_gap_open_cost;      // precalculated gap opening value (top row of nw matrix)
    unsigned int *s_horizontal_gap_extension; //
    size_t        lenLongerChar;              //

    DIR_MTX_ARROW_t  *direction_matrix;

    alignment_matrices_t *algnMtxs2dAffine = malloc( sizeof(alignment_matrices_t) );
    initializeAlignmentMtx(algnMtxs2dAffine, longChar->len, shortChar->len, costMtx2d_affine->costMatrixDimension);
    // printf("Jut initialized alignment matrices.\n");
    lenLongerChar = longChar->len;

    matrix_2d  = algnMtxs2dAffine->algn_costMtx;
    precalcMtx = algnMtxs2dAffine->algn_precalcMtx;


    algnMtx_precalc_4algn_2d( algnMtxs2dAffine, costMtx2d_affine, longChar );


    // here and in algn.c, "block" refers to a block of gaps, so close_block_diagonal is the cost to
    // end a subcharacter of gaps, presumably with a substitution, but maybe by simply switching directions:
    // there was a vertical gap, now there's a horizontal one.

    /** 2 through 11 below are offsets into various "matrices" in the alignment matrices, of which there are four
        of length 2 * longer_character and two of longer_character */
    close_block_diagonal       =  matrix_2d;
    extend_block_diagonal      = (matrix_2d + ( lenLongerChar *  2 ));
    extend_vertical            = (matrix_2d + ( lenLongerChar *  4 ));
    extend_horizontal          = (matrix_2d + ( lenLongerChar *  6 ));
    final_cost_matrix          = (matrix_2d + ( lenLongerChar *  8 ));
    precalc_gap_open_cost      = (matrix_2d + ( lenLongerChar * 10 ));
    s_horizontal_gap_extension = (matrix_2d + ( lenLongerChar * 11 ));


    // TODO: empty_medianChar might not be necessary, as it's unused in ml code:
/*    size_t medianCharLen             = CHAR_CAPACITY;
    dyn_character_t *empty_medianChar           = malloc( sizeof(dyn_character_t) );
    empty_medianChar->cap            = CHAR_CAPACITY;
    empty_medianChar->array_head     = calloc( CHAR_CAPACITY, sizeof(elem_t));
    empty_medianChar->len            = 0;
    empty_medianChar->char_begin      = empty_medianChar->end = empty_medianChar->array_head + CHAR_CAPACITY;
*/


    direction_matrix                = algnMtxs2dAffine->algn_dirMtx;

    // printf("!!!!!  HERE !!!!!\n");

    // TODO: consider moving all of this into algn.
    //       the following three fns were initially not declared in algn.h
    algn_initialize_matrices_affine ( costMtx2d_affine->gap_open_cost
                                    , shortChar
                                    , longChar
                                    , costMtx2d_affine
                                    , close_block_diagonal
                                    , extend_block_diagonal
                                    , extend_vertical
                                    , extend_horizontal
                                    , final_cost_matrix
                                    , direction_matrix
                                    , precalcMtx
                                    );

    int algnCost = algn_fill_plane_2d_affine( shortChar
                                            , longChar
                                            , shortChar->len - 1  // -1 because of a loop condition in algn_fill_plane_2d_affine
                                            , longChar->len  - 1  // -1 because of a loop condition in algn_fill_plane_2d_affine
                                            , final_cost_matrix
                                            , direction_matrix
                                            , costMtx2d_affine
                                            , extend_horizontal
                                            , extend_vertical
                                            , close_block_diagonal
                                            , extend_block_diagonal
                                            , precalcMtx
                                            , precalc_gap_open_cost
                                            , s_horizontal_gap_extension
                                            );

    if(getMedians) {
        dyn_character_t *ungappedMedianChar = malloc(sizeof(dyn_character_t));
        dyn_character_t *gappedMedianChar   = malloc(sizeof(dyn_character_t));
        initializeChar(ungappedMedianChar, CHAR_CAPACITY);
        initializeChar(gappedMedianChar,   CHAR_CAPACITY);

        algn_backtrace_affine( shortChar
                             , longChar
                             , direction_matrix
                             , ungappedMedianChar
                             , gappedMedianChar
                             , retShortChar
                             , retLongChar
                             , costMtx2d_affine
                             );

        dynCharToAlignIO(ungappedOutput_aio, ungappedMedianChar);
        dynCharToAlignIO(gappedOutput_aio,   gappedMedianChar);

        dynCharToAlignIO(longIO,  retLongChar);
        dynCharToAlignIO(shortIO, retShortChar);

        freeChar(ungappedMedianChar);
        freeChar(gappedMedianChar);
    }

    freeNWMtx(algnMtxs2dAffine);
    freeChar(retLongChar);
    freeChar(retShortChar);

    return algnCost;
}


int align3d( alignIO_t          *inputChar1_aio
           , alignIO_t          *inputChar2_aio
           , alignIO_t          *inputChar3_aio
           , alignIO_t          *ungappedOutput_aio
           , alignIO_t          *gappedOutput_aio
           , cost_matrices_3d_t *costMtx3d
           , unsigned int        gap_open_cost
           //, unsigned int        gap_extension_cost <-- This comes from tcm so is not necessary. TODO: no tcm; add this back in?
           )
{

    if (DEBUG_ALGN) {
        printf("\n\nalign3d char1 input:\n");
        printf("\ninput char 1:");
        alignIO_print(inputChar1_aio);
        printf("input char 2:");
        alignIO_print(inputChar2_aio);
    }
    printf("gap char: %u\n", costMtx3d->gap_char);

    const size_t CHAR_CAPACITY = inputChar1_aio->length + inputChar2_aio->length + inputChar3_aio->length + 3; // 3 to account for gaps,
                                                                                                               // which will be added in
                                                                                                               // initializeChar()
    unsigned int algnCost;

    alignIO_t *longIO,
              *middleIO,
              *shortIO;

    dyn_character_t *longChar      = malloc(sizeof(dyn_character_t)); // input to algn_nw_3d
    dyn_character_t *middleChar    = malloc(sizeof(dyn_character_t)); // input to algn_nw_3d
    dyn_character_t *shortChar     = malloc(sizeof(dyn_character_t)); // input to algn_nw_3d

    dyn_character_t *retLongChar   = malloc(sizeof(dyn_character_t)); // aligned character outputs from backtrace (not medians)
    dyn_character_t *retMiddleChar = malloc(sizeof(dyn_character_t)); // aligned character outputs from backtrace (not medians)
    dyn_character_t *retShortChar  = malloc(sizeof(dyn_character_t)); // aligned character outputs from backtrace (not medians)

    /*** Most character allocation is now done on Haskell side, but these three are local. ***/
    /*** longChar, middleChar and shortChar will have pointers into the input characters, so don't need to be initialized separately ***/
    initializeChar(retLongChar,   CHAR_CAPACITY);
    initializeChar(retMiddleChar, CHAR_CAPACITY);
    initializeChar(retShortChar,  CHAR_CAPACITY);


    size_t alphabetSize = costMtx3d->costMatrixDimension;

    // Now sort inputs into appropriate structs by name.
    // This will allow us to send inputs in in correct order by length and also get them back in the order
    // that corresponds to inputs.
    if (DEBUG_3D) printf("char lengths: %lu, %lu, %lu\n", inputChar1_aio->length, inputChar2_aio->length, inputChar3_aio->length);
    if (inputChar1_aio->length >= inputChar2_aio->length) {

        if (inputChar3_aio->length >= inputChar1_aio->length) {        // input 3 is longest, 2 is shortest
            alignIOtoDynChar(longChar, inputChar3_aio, alphabetSize);
            longIO = inputChar3_aio;

            alignIOtoDynChar(middleChar, inputChar1_aio, alphabetSize);
            middleIO = inputChar1_aio;

            alignIOtoDynChar(shortChar, inputChar2_aio, alphabetSize);
            shortIO = inputChar2_aio;

        } else if (inputChar3_aio->length >= inputChar2_aio->length) { // input 1 is longest, 2 is shortest
            alignIOtoDynChar(longChar, inputChar1_aio, alphabetSize);
            longIO = inputChar1_aio;

            alignIOtoDynChar(middleChar, inputChar3_aio, alphabetSize);
            middleIO = inputChar3_aio;

            alignIOtoDynChar(shortChar, inputChar2_aio, alphabetSize);
            shortIO = inputChar2_aio;

        } else {                                                       // input 1 is longest, 3 is shortest
            alignIOtoDynChar(longChar, inputChar1_aio, alphabetSize);
            longIO = inputChar1_aio;

            alignIOtoDynChar(middleChar, inputChar2_aio, alphabetSize);
            middleIO = inputChar2_aio;

            alignIOtoDynChar(shortChar, inputChar3_aio, alphabetSize);
            shortIO = inputChar3_aio;
        }

    } else { // input 2 longer than input 1
        if (inputChar3_aio->length >= inputChar2_aio->length) {        // input 3 is longest, 1 is shortest
            alignIOtoDynChar(longChar, inputChar3_aio, alphabetSize);
            longIO = inputChar3_aio;

            alignIOtoDynChar(middleChar, inputChar2_aio, alphabetSize);
            middleIO = inputChar2_aio;

            alignIOtoDynChar(shortChar, inputChar1_aio, alphabetSize);
            shortIO = inputChar1_aio;

        } else if (inputChar3_aio->length >= inputChar1_aio->length) { // input 2 is longest, 1 is shortest
            alignIOtoDynChar(longChar, inputChar2_aio, alphabetSize);
            longIO = inputChar2_aio;

            alignIOtoDynChar(middleChar, inputChar3_aio, alphabetSize);
            middleIO = inputChar3_aio;

            alignIOtoDynChar(shortChar, inputChar1_aio, alphabetSize);
            shortIO = inputChar1_aio;

        } else {                                                       // input 2 is longest, 3 is shortest
            alignIOtoDynChar(longChar, inputChar2_aio, alphabetSize);
            longIO = inputChar2_aio;

            alignIOtoDynChar(middleChar, inputChar1_aio, alphabetSize);
            middleIO = inputChar1_aio;

            alignIOtoDynChar(shortChar, inputChar3_aio, alphabetSize);
            shortIO = inputChar3_aio;
        }
    }

    if (DEBUG_3D) {
        printf("\nAfter initialization into correct data structs, long (char 1):\n");
        dyn_char_print(longChar);
        printf("\nAfter initialization into correct data structs, middle (char 2):\n");
        dyn_char_print(middleChar);
        printf("\nAfter initialization into correct data structs, short (char 3):\n");
        dyn_char_print(shortChar);
    }

    // Adding initial gap in. Still should get rid of this. Sigh.
    // longChar->array_head[0] = middleChar->array_head[0] = shortChar->array_head[0] = 16; // TODO: Look up gap cost based on
                                                                                         // alphabet length?
                                                                                         // It's also hard-coded in 3d ukk, so will have
                                                                                         // to change it there, too.

    if (DEBUG_CALL_ORDER) printf("\n---Calling Powell\n\n");

    // Powell aligns three sequences.
    algnCost = powell_3D_align ( longChar
                               , shortChar
                               , middleChar
                               , retLongChar
                               , retShortChar
                               , retMiddleChar
                               , 1                   // mismatch cost, must be > 0
                               , gap_open_cost       // must be >= 0
                               , 1                   // gap extension cost: must be > 0
                               );

    dyn_character_t *ungappedMedianChar = malloc(sizeof(dyn_character_t));
    dyn_character_t *gappedMedianChar   = malloc(sizeof(dyn_character_t));

    initializeChar(ungappedMedianChar, CHAR_CAPACITY);
    initializeChar(gappedMedianChar,   CHAR_CAPACITY);

    algnCost = algn_get_cost_medians_3d( retLongChar
                                       , retShortChar
                                       , retMiddleChar
                                       , costMtx3d
                                       , ungappedMedianChar
                                       , gappedMedianChar
                                       );



    dyn_char_print(ungappedMedianChar);
    dyn_char_print(gappedMedianChar);
    // dyn_char_print(ungappedOutput_aio);
    // dyn_char_print(gappedOutput_aio);

    printf("ungapped\n");
    dynCharToAlignIO(ungappedOutput_aio, ungappedMedianChar);
    printf("gapped\n");
    dynCharToAlignIO(gappedOutput_aio,   gappedMedianChar);

    dynCharToAlignIO(longIO,   retLongChar);
    dynCharToAlignIO(middleIO, retMiddleChar);
    dynCharToAlignIO(shortIO,  retShortChar);

    freeChar(ungappedMedianChar);
    freeChar(gappedMedianChar);

    freeChar(retLongChar);
    freeChar(retMiddleChar);
    freeChar(retShortChar);

    return algnCost;
}


void alignIO_print( const alignIO_t *character )
{
    printf("\n");
    printf("Length:   %zu\n", character->length);
    printf("Capacity: %zu\n", character->capacity);
    size_t charStart = character->capacity - character->length;
    for(size_t i = charStart; i < character->capacity; i++) {
        printf("%3d,", character->character[i]);
        //if (character->character[i] == 0) continue;
    }
    printf("\n\n");
    fflush(stdout);
}


void alignIOtoDynChar(       dyn_character_t *retChar
                     , const alignIO_t       *input
                     ,       size_t           alphabetSize
                     )
{
    // printf("\n\nInput Length:        %2zu\n", input->length  );
    // printf("Input Capacity:      %2zu\n", input->capacity);
    // printf("Input alphabetSize:  %2zu\n", alphabetSize);

    // assign character into character struct
    size_t offset       = input->capacity - input->length;
    retChar->len        = input->length;
    retChar->cap        = input->capacity;
    retChar->array_head = input->character;
    retChar->end        = input->character + input->capacity - 1;
    retChar->char_begin = input->character + offset;

    // printf("\nBefore duping struct:\n");
    // printf("Input Length:      %2zu\n", input->length);
    // printf("Input Capacity:    %2zu\n", input->capacity);
    // printf("Input Array Head:  %2d\n",  input->character[0]);
    // printf("Input First:       %2d\n",  input->character[input->capacity - input->length]);
    // printf("Input Last:        %2d\n",  input->character[input->capacity - 1]);
    // fflush(stdout);
    // memcpy(retChar->char_begin, input->character + offset, input->length * sizeof(elem_t));
    //printf("\nmemcpy completed\n");

    // now add gap to beginning
    retChar->char_begin--;   // Add another cell, prepended to the array
    *retChar->char_begin = ((elem_t) 1) << (alphabetSize - 1);   //Prepend a gap to the array.
    retChar->len++;

    // printf("\nAfter duping struct:\n");
    // printf("Output Length:     %2zu\n", retChar->len);
    // printf("Output Capacity:   %2zu\n", retChar->cap);
    // printf("Output Array Head: %2d\n",  retChar->array_head[0]);
    // printf("Output First:      %2d\n",  retChar->char_begin[0] );
    // printf("Output Last:       %2d\n",  retChar->end[0]       );
    // //printf("Gap value:           %2d\n", ((elem_t) 1) << (alphabetSize - 1));
    // fflush(stdout);

}


void allocAlignIO(alignIO_t *toAlloc, size_t capacity) {
    toAlloc->length    = 0;
    toAlloc->capacity  = capacity;
    toAlloc->character = calloc(capacity, sizeof(elem_t));
}


void copyValsToAIO(alignIO_t *outChar, elem_t *vals, size_t length, size_t capacity) {
    outChar->length   = length;
    outChar->capacity = capacity;
    // printf("here!\n");
    outChar->character = malloc( outChar->capacity * sizeof(elem_t) );
    // printf("here!!\n");
    size_t offset = capacity - length;
    // printf("\n");
    memcpy(outChar->character + offset, vals, length * sizeof(elem_t));
    // for(size_t i = 0; i < length; i++) {
    //     //outChar->character[i + offset] = vals[i];
    //     printf("copy %zu: %d, %d\n", i, vals[i], outChar->character[i + offset]);
    // }
    // printf("here!!!\n");
}


/** Takes in an alignIO and a char. *Copies* values of character from end of char to end of alignIO->character, so output must already
 *  be alloc'ed.
 *  Also eliminates extra gap at beginning of character that was needed by legacy code, as well as 0 that Powell appends to end of
 *  character.
 */
void dynCharToAlignIO(alignIO_t *output, dyn_character_t *input) {

    printf("input:\n");
    printf("  Length:   %zu\n", input->len);
    printf("  Capacity: %zu\n", input->cap);
    printf("output:\n");
    printf("  Length:   %zu\n", output->length);
    printf("  Capacity: %zu\n", output->capacity);
    fflush(stdout);

    size_t  copy_length;    // These two because ungapped characters will have their initial gaps removed, so may be length 0.
    elem_t *input_begin;

    // Now set length to copy and copy initial read location.
    // If input length > 0, Decrement because of the leading gap.
    // Ungapped character already has had initial gap removed.
    // Likewise, copy start has different setting for two conditions.
    if (input->len == 0) {
        copy_length = 0;
        input_begin = input->char_begin;
    } else {
        copy_length = input->len - 1;
        input_begin = input->char_begin + 1;
    }

    output->length = copy_length;
    // output->capacity = input->cap;     // this shouldn't change
    size_t offset  = output->capacity - copy_length; // How far into output to start copying input character.

    output->character = malloc( output->capacity * sizeof(elem_t) );

    // Start copy after unnecessary gap char in input, if it exists.
    memcpy( output->character + offset, input_begin, copy_length * sizeof(elem_t) );

}


void freeAlignIO(alignIO_t *toFree) {
    free(toFree->character);
    free(toFree);
}


void reallocAlignIO(alignIO_t *toAlloc, size_t capacity) {
    toAlloc->length    = 0;
    toAlloc->capacity  = capacity;
    toAlloc->character = realloc(toAlloc->character, capacity * sizeof(elem_t));
    if (toAlloc->character == NULL) printf("Out of memory."), exit(1);
}


void resetAlignIO(alignIO_t *inChar) {
    memset(inChar->character, 0, inChar->capacity * sizeof(elem_t));
    inChar->length = 0;
    // for(size_t i = 0; i < inChar->capacity; i++) {
    //     inChar->character[i] = 0;
    // }
}