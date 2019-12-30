#!/bin/bash


if [ ! -d /home/npres.local/mlu ]
then
if [ ! -d /home/npres.local ]
then
sudo mkdir /home/npres.local
fi
sudo ln -s /home/mlu@npres.local /home/npres.local/mlu
fi
