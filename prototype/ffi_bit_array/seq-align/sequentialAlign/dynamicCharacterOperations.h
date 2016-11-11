/**
 *  Contains various helper fns for using bit arrays to implement packed dynamic characters.
 *  Individual dynamic character elements are represented using bit arrays, where each bit marks whether
 *  a given character state is present in that element, so [1,0,0,1] would imply that the element is
 *  ambiguously an A or a T.
 *  The length of each element is thus the length of number of possible character states (the alphabet).
 *
 *  To clarify the nomenclature used in this file,
 *  • A dynamic character element (DCElement) is a single, possibly ambiguous phylogenetic character, e.g.,
 *    in the case of DNA, A or {A,G}.
 *  • A series of DCElements are "packed" if they are concatenated directly,
 *    and not stored one to each array position. Each array position might therefore hold many elements.
 *    For instance, one might store characters with alphabet size 4 in an array of int64s.
 *    In that case 16 elements would fit in each int in the array.
 *    Likewise, it's possible that only the first part of an element might fit into a single
 *    position in the array.
 *  • A dynamic character is a packed series of elements. (This isn't the _actual_ definition
 *    of a dynamic character, but will do for our purposes.)
 *
 *  TODO: for this to be useable on |alphabet including gap| > 64, various uint64_t types below will have to be 
 *        exchanged out for packedChar_p (i.e. arrays of 64-bit ints).
 */

#ifndef DYNAMIC_CHARACTER_OPERATIONS
#define DYNAMIC_CHARACTER_OPERATIONS

/**
 *  stdint is a library that provides int values for all architectures. This will allow the code to
 *  compile even on architectures on which int != 32 bits (and, more to the point, unsigned long int != 64 bits).
 */
#include <stdint.h>

// these must be static to prevent compilation issues.
static const size_t   BITS_IN_BYTE   = 8;  // so bytes are set to 8, for all architectures
static const size_t   INT_WIDTH      = sizeof(uint64_t);
static const size_t   WORD_WIDTH     = BITS_IN_BYTE * INT_WIDTH; // BITS_IN_BYTE * INT_WIDTH; <-- because HSC is dumb!
static const uint64_t CANONICAL_ONE  = 1;
static const uint64_t CANONICAL_ZERO = 0;

typedef uint64_t* packedChar_p;

/* alignResult_t is where results get put for return to Haskell */
typedef struct alignResult_t {
    size_t       finalWt;
    size_t       finalLength;
    packedChar_p finalChar1;
    packedChar_p finalChar2;
} alignResult_t;

/**
 *  This holds the array of _possibly ambiguous_ static chars (i.e. a single dynamic character),
 *  along with its alphabet size and the number of "characters" (dcElements) in the dynChar.
 *  See note in .c file for how this is used.
 */
typedef struct dynChar_t {
    size_t       alphSize;
    size_t       numElems;     // how many dc elements are stored
    size_t       dynCharLen;   // how many uint64_ts are necessary to store the elements
    packedChar_p dynChar;
} dynChar_t;

typedef struct dcElement_t {
    size_t       alphSize;
    packedChar_p element;
} dcElement_t;

typedef struct costMtx_t {
    int subCost;
    int gapCost;
} costMtx_t;

/**
 *  The following three functions taken from http://www.mathcs.emory.edu/~cheung/Courses/255/Syllabus/1-C-intro/bit-array.html
 *  Provides operations to use an array of ints as an array of bits. In essence, creates a mask of length k and uses that
 *  mask to set, clear and test bits.
 */
void SetBit( packedChar_p const arr, const size_t k );

void ClearBit( packedChar_p const arr, const size_t k );

uint64_t TestBit( packedChar_p const arr, const size_t k );

/** Clear entire packed character: all bits set to 0; 
 *  packedCharLen is pre-computed dynCharSize() 
 */
void ClearAll( packedChar_p const arr, const size_t packedCharLen);

/* figures out how long the int array needs to be to hold a given dynamic character */
size_t dynCharSize(size_t alphSize, size_t numElems);

size_t dcElemSize(size_t alphSize);

/** functions to free memory **/
void freeDynChar( dynChar_t* p );

void freeDCElem( dcElement_t* p );

/** functions to interact directly with DCElements */

/** returns the correct gap value for this character */
uint64_t getGap(const dynChar_t* const character);

/**
 *  Takes in a dynamic character to be altered, as well as the index of the element that will
 *  be replaced. A second input is provided, which is the replacement element.
 *  Fails if the position of the element to be replaced is beyond the end of the dynamic character to be altered.
 *  Fails if the alphabet sizes of the two input characters are different.
 *  Makes a copy of value in changeToThis, so can deallocate or mutate changeToThis later with no worries.
 */
int setDCElement( const size_t whichIdx, 
                 const dcElement_t* const changeToThis, dynChar_t* const charToBeAltered );

/**
 *  Find and return an element from a packed dynamic character.
 *  Return failure (indicted as an alphabet size of 0) if:
 *  • character requested is beyond end of dynamic character's length
 *  • the alphabet sizes of the input and output characters don't match
 *
 *  This allocates, so must be 
 *      a) NULL checked, 
 *      b) freed later using deallocations, above.
 */
dcElement_t* getDCElement( const size_t whichChar, const dynChar_t* const indynChar_t);

/**
 *  Create an empty dynamic character element (i.e., a dynamic character with only one sub-character)
 *  using inputted alphabet length to determine necessary length of internal int array.
 *  Fill internal int array with zeroes.
 *  This allocates, so must be 
 *      a) NULL checked, 
 *      b) freed later using deallocations, above.
 */
dcElement_t* makeDCElement( const size_t alphSize, const uint64_t value );

/**
 *  Send in two elements. If there's an overlap, put that overlap into return dyn char, return 0.
 *  Otherwise, compute least cost and return that cost and put the median into return dynChar.
 *
 *  If the two characters are not compatible (have different length alphabets—it doesn't check 
 *  to see that the alphabets are the same), returns a negative cost.
 */
double getCost( const dynChar_t* const inDynChar1, size_t whichElem1, 
                const dynChar_t* const inDynChar2, size_t whichElem2, 
                costMtx_t* tcm, dcElement_t* newElem1 );

/** Allocator for dynChar_t
 *  This (obviously) allocates, so must be 
 *      a) NULL checked, 
 *      b) freed later using deallocations, above.
 */
dynChar_t* makeDynamicChar( size_t alphSize, size_t numElems, packedChar_p values );

/** takes as input a dynamic character and converts it to a uint64_t array. Allocates, so after returned array
 *  is no longer in use it must be deallocated.
 */
int* dynCharToIntArr( dynChar_t* input );

/** takes as input an int array and copies its values into a packed dynamic character.
 *  This effectively recapitulates makeDynamicChar(), with one difference, this is intended to 
 *  *copy* the contents, so it requires a preallocated dynChar_t. This is so that it can be placed
 *  into a container allocated on the other side of the FFI, and deallocated there, as well.
 */
void intArrToDynChar( size_t alphSize, size_t arrayLen, int* input, dynChar_t* output );

/** As above, but only allocates and fills the bit array, not whole dyn char */
packedChar_p intArrToBitArr( size_t alphSize, size_t arrayLen, int* input );

dcElement_t* dcElementOr (dcElement_t* lhs, dcElement_t* rhs);

packedChar_p packedCharOr (packedChar_p lhs, packedChar_p rhs, size_t alphSize);

#endif /* DYNAMIC_CHARACTER_OPERATIONS */