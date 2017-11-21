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

#ifndef DYN_CHAR_H
#define DYN_CHAR_H


#define USE_LARGE_ALPHABETS


// #ifdef USE_LARGE_ALPHABETS
#define elem_t unsigned int


/* Dynamic character structure to be used inside ocaml custom types. */
/********************* CHARACTER AS IT COMES IN MUST BE IN LAST X SPACES IN ARRAY! *********************/
typedef struct dyn_character_t {
    size_t  cap;        // Capacity of the character memory structure.
    size_t  len;        // Total length of the character stored.
    elem_t *array_head; // beginning of the allocated array
    elem_t *char_begin; // Position where the first element of the character is actually stored.
    elem_t *end;        // End of both array and character.
} dyn_character_t;


/** Does internal allocation for a character struct. Also sets character pointers within array to correct positions.
 *
 *  resChar must be alloced before this call. This is because allocation must be done on other side of FFI for pass
 *  by ref to be correct.
 */
void dyn_char_initialize( dyn_character_t *retChar
                        , size_t           allocSize );


/** Adds value to the front of character. Increments the length of a and decrements the head of the character. */
void dyn_char_prepend( dyn_character_t *character
                     , elem_t           value
                     );


void dyn_char_print( const dyn_character_t *inChar );


/** Resets character array to all 0s.
 *  Makes length 0.
 *  Points beginning of character to end of character array.
 */
void dyn_char_resetValues( dyn_character_t *retChar );


/* Stores value in position on character. */
void dyn_char_set( dyn_character_t *character
                 , size_t           position
                 , elem_t           value
                 );

#endif /* DYN_CHAR_H */
