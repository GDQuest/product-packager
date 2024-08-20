#!/usr/bin/env bash
mkdir -p mdx-utils && \
cd src && \
nim c -o:../mdx-utils/gdschool_preprocess_mdx gdschool_preprocess_mdx.nim 