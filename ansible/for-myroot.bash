#!/bin/bash

ansible-playbook -i /home/mlu@npres.local/ansible/config/mymariadbhost /home/mlu@npres.local/ansible/playbooks/for-myroot.yml
ansible-playbook -i /home/mlu@npres.local/ansible/config/badhost  /home/mlu@npres.local/ansible/playbooks/for-myroot-badhost.yml
