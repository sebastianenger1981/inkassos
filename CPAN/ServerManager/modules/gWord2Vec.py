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

logging.basicConfig(format='%(asctime)s : %(levelname)s : %(message)s', level=logging.INFO)

try:
    import gensim
except NameError:
    print('gensim is not installed')


logging.root.setLevel(level=logging.INFO)

f = codecs.open('versicherung.txt', 'r', 'ISO-8859-1')
text = f.read()

model = gensim.models.Word2Vec()
sentences = gensim.models.word2vec.LineSentence(f)

bigram_transformer = gensim.models.Phrases(sentences)
model = gensim.models.Word2Vec(bigram_transformer[sentences], size=200, sorted_vocab=1, alpha=0.5000,
                               max_vocab_size=10000, iter=10, window=2, min_count=2,
        workers=multiprocessing.cpu_count())

# trim unneeded model memory = use(much) less RAM
model.init_sims(replace=True)
model.save_word2vec_format("versicherung.bin", binary=True)
