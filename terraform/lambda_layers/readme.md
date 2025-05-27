## Build packages

'docker run -it python:3.8 /bin/bash'

mkdir -p requests/python

cd requests/python

pip install requests -t .

apt update && apt install -y zip


cd ..

zip -r9 ../requests.zip .

From there, you can just open another terminal and use docker cp to get the zip file to your host machine.

docker ps 

docker cp f2f6d65ad283:/requests.zip ~/Documents/Data_Engineering/terraform/lambda/requests.zip

### Build env with python

'sudo apt update
sudo apt install python3 python3-pip python3-ven'


'python3 -m venv myenv'


'source myenv/bin/activate'

install pakages 
pip install requests

'cd myenv/lib/python3.13/site-packages'

'zip -r ../../../../my_deployment_package.zip .'



### Ref

[build package](https://blog.shellnetsecurity.com/2023/04/585/cloudstuff/aws/how-to-use-terraform-to-deploy-a-python-script-to-aws-lambda/)