#!/usr/bin/env python3
# pip3 install -U textblob-de
# python3 -m textblob.download_corpora

#
# Author: Sebastian Enger, M.Sc.
# Date: 4/12/2016
# Website: www.OneTIPP.com
# Email: Sebastian.Enger@gmail.com
# Topic: Noun Sentence Extraction for Training Data Creation
# Version: 1.0.0
#

from textstat.textstat import textstat
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

f = codecs.open(input_file, 'r', 'ISO-8859-1')
text = f.read()

print(textstat.flesch_reading_ease(text))
