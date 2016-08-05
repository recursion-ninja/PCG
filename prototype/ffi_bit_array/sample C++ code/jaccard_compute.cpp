// this program computes two related ambiguities for the languages in the LD domain// first, it computes Alpha_Jaccard, which is simply the Jaccard coefficient// of each language (intersection over union, where languages are viewed as sets of// sentences), summed over all other languages, and then averaged. // Then it computes Alpha_naive, which is the intersection over the size of target language#include <set>#include <map>#include <string>#include <fstream>#include <iostream>#include <vector>#include <sstream>using namespace std;// returns size of intersection of two setsint intersectsize (set<int>&  A, set<int>& B){	int numInCommon =0;	if (A.size()<B.size())	{		for (set<int>::iterator it=A.begin(); it!=A.end(); it++)	    numInCommon += (B.find(*it)!=B.end()) ? 1 : 0 ;	}	else	{		for (set<int>::iterator it=B.begin(); it!=B.end(); it++)	    numInCommon += (A.find(*it)!=A.end()) ? 1 : 0 ;	}	return numInCommon ;}// returns size of union of two setsint unionsize (set<int>&  A, set<int>& B){	return (A.size()+B.size());}void load_LDIDs(istream& is, multimap<int,int>& M, set<int>& Gs){	int grammID, sentID, junk;	while (!is.eof())	{		is >> grammID ;		// file I'm working from has only two entries per line:		is >> sentID  ;		// "grammar \t sentence"		is >> junk;		Gs.insert(grammID);		M.insert(make_pair(grammID, sentID));	}	cout << "FINISHED loading LD_ID's " << endl ; }// used in dec2bin fnstring binary(int num) {	string rest;	string remain;	ostringstream myStream;	// for converting int to string	if (num <= 1)	{		myStream << num;		rest = myStream.str();	}	else	// num can still be subdivided	{			myStream << (num % 2);		remain = myStream.str();		rest = binary(num >> 1) + remain;	}	return rest;}// converts decimal to binary number and returns result as string of length 13string dec2bin(int num) {		string result = binary(num);	int len = result.length();		for ( int i = 13 - len; i > 0; i-- )	{		result = "0" + result;	}		return result;}int main(){	// /Volumes/Backup/eric/school/Linguistics/LD with William/	// /Users/eric/Documents/Backup/school/LD with William/	// /home/LD/LD_data/	string filepath = "/Volumes/Backup/eric/school/Linguistics/LD with William/";		ofstream jaccOut( (filepath + "jaccard_alpha.txt").c_str() );	if(!jaccOut) { cout << "Jaccard file no good" << endl; exit(1); }		ifstream ifData( (filepath + "ld_ids.txt").c_str() );	if (!ifData) { cout << "File open No Good ..." << endl ; exit(1); }	set<int> GrammSet;	multimap <int,int> GrammSentMap ;	load_LDIDs (ifData, GrammSentMap, GrammSet);		set<int>::iterator si, sj;	multimap <int, int>:: iterator lb, ub, l1it, l2it ; // upper bound, lower bound, language iterator (lit)	set<int> L1, L2 ; // language 1, language 2	int grammCount = 0;	for (si=GrammSet.begin(); si!=GrammSet.end(); si++)	{  // for every grammar (i.e. 3,072)		// fill up  L1		lb = GrammSentMap.lower_bound(*si); 		ub = GrammSentMap.upper_bound(*si);		for (l1it=lb; l1it!=ub; l1it++){L1.insert( l1it->second ); }  // (*l1it).second		// now for all remaining grammars, fill up L2		sj = si;  // si is iterating over the set of grammars,  		sj++;     // sj now is pointing to the grammar to the left of where si is pointing.		grammCount++; 		cout << "In L1 loop, Working on grammar number:"<< grammCount << endl ;		for ( ; sj != GrammSet.end(); sj++)		{			// fill up L2 (note we're using sj to iterate for the L2 languages			lb = GrammSentMap.lower_bound(*sj); 			ub = GrammSentMap.upper_bound(*sj);			for (l2it=lb; l2it!=ub; l2it++)			{				L2.insert( l2it->second ); // (*lit).second			}  			// we now have L1 and L2 filled with sentences			int intersectionSz = intersectsize(L1,L2);			int unionSz        = unionsize(L1,L2) - intersectionSz;			double jaccard   = double(intersectionSz) / double(unionSz) ;			string gName;						jaccOut << dec2bin(*si) << "\t";			jaccOut << *si << "\t";			jaccOut << L1.size() << "\t";			jaccOut << dec2bin(*sj) << "\t";			jaccOut << *sj << "\t";			jaccOut << L2.size() << "\t";			jaccOut << jaccard << "\n" ;			L2.clear();		} // end of inside L2 loop				L1.clear() ; 	} 		}