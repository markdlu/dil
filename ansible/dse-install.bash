#!/bin/bash

ansible-playbook -i /home/mlu@npres.local/ansible/config/myansiblehost /home/mlu@npres.local/ansible/playbooks/dse-install.yml --extra-vars "myip=10.65.28.72"
