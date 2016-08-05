// this program computes two related ambiguities for the languages in the LD domain// first, it computes Alpha_Jaccard, which is simply the Jaccard coefficient// of each language (intersection over union, where languages are viewed as sets of// sentences), summed over all other languages, and then averaged. // Then it computes Alpha_naive, which is the intersection over the size of target language#include <set>#include <map>#include <string>#include <fstream>#include <iostream>#include <vector>using namespace std;const int GRAMMAR_COUNT = 3072;	// note: i consider this a design flaw which must repaired prior to library								// creation. It's needed for the build matrix loop, in which vectors of size								// GRAMMAR_COUNT are added to the matrix. GRAMMAR_COUNT is the number of grammars								// in a given database (here the LD).// ddeletes trailing spaces on sentences from LDvoid deleteTrailSpaces(string& sentence){	int length = sentence.length();	while( sentence[length - 1] == ' ')	{		sentence.erase(length - 1, 1);		length--;	}}void mapPrint( map<int, float>& alpha, map<string, int>& index, ofstream& fileOut ){	for( map<string, int>::const_iterator it = index.begin() ; it != index.end(); it++ )	{			fileOut << (*it).first << "\t" << alpha[ (*it).second ] << "\n";	}}	//computes (L_x intersect L_i) /(L_x union L_i), where L_x is a given grammar and i != x void computeUnweightedAlphas( vector< vector<bool> >& sgMatrix, map<int, int>& gCount, ofstream& naiveOut, ofstream& jaccOut, map<string, int>& gIndex ){	map<int, float> naiAlph;	// to hold naive Alphas of each grammar	map<int, float> jaccAlph;	// to hold Jaccard Alphas of each grammar	map<int, map<int, int> > gIntersections;	// this is intersection of two grammars		float jacTotal;		// to hold results of equations in second for loop	float naiTotal;		// step through grammars	for( int gramIndex = 0; gramIndex < gCount.size(); gramIndex++ )	{		// for each grammar, and for each sentence		for( int sentIndex = 0; sentIndex < sgMatrix.size(); sentIndex++ )		{			// if that grammar:sentence combo is in matrix, then step through all other grammars			// and check if each of other grammar:sentence pairs exist. If they do, then increment 			// the gIntersections for that grammar:grammar pair			if( sgMatrix[sentIndex][gramIndex] == true )			{				for( int i = gramIndex + 1; i < gCount.size(); i++)				{					if( sgMatrix[sentIndex][i]  == true )					{						gIntersections[gramIndex][i]++;					}				}			} // end if		}		if( gramIndex % 100 == 0 ) cout << "Loop one language # " << gramIndex << endl;	}		for( int gram1 = 0; gram1 < gCount.size(); gram1++ )	{		for( int gram2 = gram1 + 1; gram2 < gCount.size(); gram2++ )			// for each grammar:grammar pair, get intersection and union, divide I by U, and add to both grammars		{							// now compute unweighted versions			naiTotal = jacTotal = gIntersections[gram1][gram2];			jacTotal /= float(gCount[gram1] + gCount[gram2] - jacTotal);			jaccAlph[gram1] += jacTotal;			jaccAlph[gram2] += jacTotal;			naiAlph[gram1] += (naiTotal / gCount[gram1]);			naiAlph[gram2] += (naiTotal / gCount[gram2]);		}		jaccAlph[gram1] /= gCount.size() - 1;	// this averages over all grammars 		naiAlph[gram1] /= gCount.size() - 1;				if( gram1 % 100 == 0 ) cout << "Loop two language # " << gram1 << endl;	}	mapPrint( naiAlph, gIndex, naiveOut );	// to print naive alphas	mapPrint( jaccAlph, gIndex, jaccOut );	// to print jaccard alphas	}void buildMatrix( ifstream& ifData, map<string, int>& sIndex, map<string, int>& gIndex, vector< vector<bool> >& sgMatrix, 				  map<int, int>& sCount, map<int, int>& gCount ){	string sentence, gramID, garbage;	int grammars = GRAMMAR_COUNT;	int sCurIndex = 0;	// keep track of current # of sentences	int gCurIndex = 0;	// same, but for grammars	bool gExists = false;  // this is for use in our nested if flowchart, below.						   // it lets us know if a given sentence is new to a grammar or not	bool sExists = false;	// as above, but for sentences			// load data from LD, one sentence at a time	while (!ifData.eof() )	{		getline( ifData, gramID, '\t' );		getline( ifData, sentence, '\t' );				sCurIndex = atoi( sentence.c_str() );		gCurIndex = atoi( grammar.c_str() );			// first see if grammar exists		if (gIndex.find(gramID) == gIndex.end() )			// if the grammar has not yet been encountered, first update 		{			gIndex[gramID] = gCurIndex;			gCurIndex++;				// since grammar didn't exist, we need to initialize it in gCount and make it 1			gCount[ (gIndex[gramID]) ] = 1;		}					else	// if grammar already existed, we need to note that, to know later whether to increment gCount		{			gExists = true;		}					// check to see if sentence has previously been encountered		if( sIndex.find(sentence) == sIndex.end() )		{			sIndex[sentence] = sCurIndex;			sCurIndex++;						// now add a new sentence to the matrix, with an empty grammar list			vector<bool> foo( grammars, false);			sgMatrix.push_back(foo);						sCount[ (sIndex[sentence]) ] = 1;		} 				else		{			sExists = true;			}// end if, now sentence and grammar are indexed. 						// now make the element of the matrix relating to this sentence/grammar true		if( sgMatrix[ (sIndex[sentence]) ][ (gIndex[gramID]) ] == false )		{			if( gExists == true )	// so they don't exist together, but it hasn't also just been initialized.			{				gCount[ (gIndex[gramID]) ]++;			}			if( sExists == true )			{				sCount[ (sIndex[sentence]) ]++;			}						sgMatrix[ (sIndex[sentence]) ][ (gIndex[gramID]) ] = true;		}				sExists = false;		gExists = false;				}}int main(){	// /Volumes/Backup/eric/school/Linguistics/LD with William/	// /Users/eric/Documents/Backup/school/LD with William/	// /home/eric/LD_data/	string filepath = "/Volumes/Backup/eric/school/Linguistics/LD with William/";			ifstream ifData( (filepath + "shortLD.txt").c_str() );	ofstream naiveOut( (filepath + "naive_alpha.txt").c_str() );	ofstream jaccOut( (filepath + "jaccard_alpha.txt").c_str() );		map<string, int> sIndex; 	// to give each sentence a unique ID, for vector lookup	map<string, int> gIndex; 	// same as above, but for grammars		map<int, float> naiWeiAlph;	// holds naive Alphas, but computed using sentence weighting fn	//map<int, float> jaccWeiAlph;	// as with naiWeiAlph, above	map<int, float> langAmbig;	// holds average of weights of sentences in language		map<int, int> sCount; 	// keeps track of number of unique grammars a sentence has appeared in,							// using the sentence ID as an index	map<int, int> gCount; 	// keeps track of unique sentences in each grammar, as above		vector< vector<bool> > sgMatrix;	// to hold a matrix of bits saying whether a given sentence is in a grammar										// sgMatrix[1][2] would access sentence 1 in grammar 2		buildMatrix( ifData, sIndex, gIndex, sgMatrix, sCount, gCount );	cout << "Matrix done." << endl;	//printMatrix( sgMatrix, sIndex );	computeUnweightedAlphas( sgMatrix, gCount, naiveOut, jaccOut, gIndex );	}