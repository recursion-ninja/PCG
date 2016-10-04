#include <stdio.h> 
#include <stdlib.h>
#include <string.h> 
#include "bitArrayTestC.h"

/** 
 *  The following fn should only needed this for testing, so it's not in the .h file. 
 *
 *  Prints a representation of a dynamic character as a matrix of bits.
 */
void printBits( dynChar_t* input ) {
  printf("[\n");
  unsigned int alphLen = input -> alphSize;
  unsigned int numDCElements = input -> numElems;

  for( unsigned int charNum = 0; charNum < numDCElements; charNum++ ) {
    for( unsigned int bitIdx = 0; bitIdx < alphLen; bitIdx++ ) {
      if( TestBit(input -> dynChar, alphLen * charNum + bitIdx) ) {
	//printf("Bit index:        %d\n", alphLen * charNum + bitIdx );
	printf("1,");
      } else {
	printf("0,");
      }
    }
    printf("\n");
  }
  printf("]\n");
}

/** 
 *  A sample program that takes in two dynamic characters, and wrote the result of any computations to a third
 *  dynamic character. The third character is allocated on Haskell side and passed in by reference.
 *  Returns 0 on correct exit, 1 on allocation failure. This was used to test the Haskell FFI.
 */
int exampleInterfaceFn(dynChar_t* seqA, dynChar_t* seqB, alignResult_t* result) {
    // Because the characters are packed (meaning multiple characters will be in a single int,
    // we need the total number of ints in our array, which is 
    size_t buffLenA = bufferSize(seqA);   
    size_t buffLenB = bufferSize(seqB);

    // Using calloc out of an abundance of caution. Shouldn't need it, as we overwrite the entire buffer.
    // This will have to be freed in the Haskell end of things.
    // See note in .h file re: uint64_t
    uint64_t* buffer = (uint64_t*) calloc( buffLenA + buffLenB, INT_WIDTH); // in bytes. int array, so don't need \0

    // Now check that calloc() didn't fail.
    if( buffer == NULL ) {
        return 1;
    }
    
    // a simple concatenation, to test the input and output. Note that this won't be packed; we're just 
    // sticking the two arrays together.
    for(int i = 0; i < buffLenA; i++) {
        buffer[i] = seqA -> dynChar[i];
    }
    
    for(int i = 0; i < buffLenB; i++) {
        buffer[i + buffLenA] = seqB -> dynChar[i];
    }

    // now assign to struct for retrieval by Haskell FFI
    result->finalWt     = buffLenA + buffLenB; // Real cost goes here later
    result->finalLength = buffLenA + buffLenB;
    result->finalStr    = buffer;
    return 0;
}

/** 
 *  The following fn should only needed this for testing, so it's not in the .h file. 
 *
 *  Takes in a dynamic character (by reference), an alphabet length, the number of static
 *  characters the array should hold, and an array of int values that should be packed into the
 *  the character. Then mutates the passed character to match the inputs.
 */
void makeDynamicChar( dynChar_t* output, unsigned int alphLen, unsigned int numDCElements, uint64_t* values ) {
  // First create dynamic character with empty character field.
  output -> alphSize   = alphLen;
  output -> numElems = numDCElements;

  // Now figure out how many uint64_t's we'll need in our array.
  // Then declare and initialize a dynChar.
  size_t neededLen = bufferSize(output);

  // need to alloc so that array isn't on the stack, and persist beyond this function call
  output -> dynChar = (uint64_t*)  calloc( neededLen, INT_WIDTH );
  // fill array with integer values,
  for( int charNum = 0; charNum < numDCElements; charNum++ ) {
    for( int bitIdx = 0; bitIdx < alphLen; bitIdx++ ) {
      if( values[charNum] & (1 << bitIdx) ) {
	SetBit(output -> dynChar, charNum * alphLen + bitIdx);
      }
    }
  }
}

/**
 *  This function purely for testing, and as example usage.
 */
int main() {
    size_t numDCElements = 14;
    size_t alphabetLen    = 5;
    uint64_t values [numDCElements];
    for( size_t i = 0; i < numDCElements; i++ ) {
        values[i] = (uint64_t) i;
    }

    // testing makeDynamicChar

    // creating with more than one int necessary in the array
    dynChar_t char1; // alphabet: 5, chars: 14, values: 0 .. 13
    makeDynamicChar(&char1, alphabetLen, numDCElements, values);
    printf("\nTest bit wrap to next int. Should be 14 elements and alphabet length 5, then numbers from 0 to 14 in bits:\n");
    printf("No. of elements: %zu\n", char1.numElems);
    printf("Alphabet length: %zu\n", char1.alphSize);
    printBits(&char1);

    // testing this with a large alphabet size. Still needs to be amended.
    printf("\nTest make static character. Should be 1 elements and alphabet length 63, then a matrix 63 wide, all set to 0 except first three:\n");
    alphabetLen = 63; // TODO: fix this so it rolls over. Right now 64 is max.
    dcElement_t char2; // alphabet: 63, chars: 1, value: 7
    makeDCElement( alphabetLen, (uint64_t) 7, &char2 ); // cast because input needs to be unsigned long
    printf("No. of elements: %zu\n", char2.numElems);
    printf("Alphabet length: %zu\n", char2.alphSize);
    printBits( &char2 );

    printf("\nTest accessors:\n");

    // first, try getting a static character from char1 and assiging it int char3
    alphabetLen = 5;
    printf("\nTest get static character. Should be 1 elements and alphabet length 5, then an element with value 13 (in binary), then error out twice:\n");
    dcElement_t char3; // alphabet: 5, chars: 1, value: 13
    makeDCElement( alphabetLen, (uint64_t) 0, &char3 );
    if ( getDCElement( (unsigned int) 13, &char1, &char3) ) { //note that failing returns a 1, so "true, it failed"
        printf("Error! \n");
    } else {
        printf("No. of elements: %zu\n", char3.numElems);
        printf("Alphabet length: %zu\n", char3.alphSize);
        printBits( &char3 );
    }

    // now fail because there aren't 17 static chars in char1
    if ( getDCElement( (unsigned int) 17, &char1, &char3) ) {
        printf("\nError!\n");
    } else {
        printBits( &char3 );
    }

    // now fail because alphabet sizes aren't the same
    char3.alphSize = 7;
    if ( getDCElement( (unsigned int) 13, &char1, &char3) ) {
        printf("\nError!\n");
    } else {
        printBits( &char3 );
    }


    printf("\nTest set static character. Should print matrix with binary ints from 0 to 13, with evens all replace by 13, then error out twice:\n");

    // now set the value of char3 into char1 at all even positions.
    char3.alphSize = 5;
    for( unsigned int i = 0; i < char1.numElems; i+=2 ) {
        if ( setDCElement( i, &char3, &char1 ) ) {
            printf("Error! \n");
            break;
        } 
    }
    printBits( &char1 );
    
    // Fail because index is beyond length of char1
    if ( setDCElement( (unsigned int) 17, &char1, &char3) ) {
        printf("\nError!\n");
    } else {
        printBits( &char3 );
    }

    // fail because alphabets are different lengths
    char3.alphSize = 7;
    if ( setDCElement( (unsigned int) 13, &char1, &char3) ) {
        printf("\nError!\n\n\n");
    } else {
        printBits( &char3 );
    }

}