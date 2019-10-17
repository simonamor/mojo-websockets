#!/bin/bash

CL=$1
if [ -z "$CL" ]
then
    echo "Need a client id"
    exit
fi
curl  -k -d "id=$CL" -d 'msg={"text":"Hello World"}' http://localhost:3019/send

echo
