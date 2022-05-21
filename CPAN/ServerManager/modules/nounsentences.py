#!/usr/bin/env python3
# pip3 install -U textblob-de
# python3 -m textblob.download_corpora

#
# Author: Sebastian Enger, M.Sc.
# Date: 3/20/2016
# Website: www.OneTIPP.com
# Email: Sebastian.Enger@gmail.com
# Topic: Noun Sentence Extraction for Training Data Creation
# Version: 1.0.0
#

from textblob_de import TextBlobDE as TextBlob
import sys, getopt
import codecs

version = '1.0'
verbose = False

#print 'ARGV      :', sys.argv[1:]

options, remainder = getopt.getopt(sys.argv[1:], 'i:v', ['output=',
                                                         'verbose',
                                                         'version=',
                                                         ])
#print 'OPTIONS   :', options

for opt, arg in options:
    if opt in ('-i', '--inpput'):
        input_file = arg
    elif opt in ('-v', '--verbose'):
        verbose = True
    elif opt == '--version':
        version = arg

#print 'VERSION   :', version
#print 'VERBOSE   :', verbose
#print 'REMAINING :', remainder


f = codecs.open(input_file, 'r', 'UTF-8')
text = f.read()

blob = TextBlob(text)
np = blob.noun_phrases
for e in np:
    words = e.split()
    f = 0
    for w in words:
        #print("word:"+w)
        if w[0].isupper() and len(w)>=3:
        #    print("wordUpper:"+w)
            f = 1
    if f == 1:
        print(e+";")