#!/usr/bin/env python
# -*- coding: utf-8 -*-

import os.path
import sys
import multiprocessing
# pip install --upgrade gensim
# easy_install -U gensim
# wget https://bootstrap.pypa.io/ez_setup.py -O - | python

import logging
import gensim.models
import codecs

try:
    import gensim
except NameError:
    print('gensim is not installed')


logging.root.setLevel(level=logging.INFO)

model = gensim.models.Word2Vec()

model.load_word2vec_format("versicherung.bin", binary=True)

model.most_similar(positive=["Versicherung","Geld"], negative=["Asche"], topn=10, restrict_vocab=None)

#model.n_similarity(['Versicherung', 'Hausrat'])