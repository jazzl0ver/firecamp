AWS ECS currently does not support to specify volume driver. See ECS Open Issue [Volume Driver support](https://github.com/aws/amazon-ecs-agent/issues/236). Once AWS ECS supports the custom volume driver, there is no need to patch ecs-agent.

Apply patch aws-ecs-agent.patch by:
cp aws-ecs-agent.patch ~/firecamp/amazon-ecs-agent; cd ~/firecamp/amazon-ecs-agent; patch -p1 < aws-ecs-agent.patch

or manually:
1. copy firecamp_task_engine.go to jazzl0ver/amazon-ecs-agent/agent/engine/
2. apply patches from the patches/ folder
3. update VERSION (for example, to v1.79.0-firecamp)
4. authenticate to AWS ECR public repo:
aws ecr-public get-login-password --region us-east-1 | docker login --username AWS --password-stdin public.ecr.aws

Then simply sudo make to build the ecs-agent container image and issue:
docker push jazzl0ver/firecamp-amazon-ecs-agent:latest

To manually run the agent container, please initialize the agent first.
1. Initialize jazzl0ver/amazon-ecs-agent on EC2 for the first time, run start_ecs_agent.sh.
2. If the system is reboot after ecs-agent initialized, run: docker start ecs-agent-containerID.

We also fork the [Amazon ECS Init](https://github.com/jazzl0ver/amazon-ecs-init) to directly load the ECS Agent container image from docker hub. The FireCamp cluster auto deployment (AWS CloudFormation) will automatically download the Amazon ECS Init RPM from CloudStax S3 bucket and install on the node. The ECS Init will manage the [CloudStax Amazon ECS Container Agent](http://github.com/jazzl0ver/amazon-ecs-agent).

Docker plugin is uniquely identified by the plugin name and version, such as jazzl0ver/firecamp-volume:v1. The ECS service task definition will include the current version as environment variable. So ECS Agent patch could get the version and set the plugin name correctly.


https://help.github.com/articles/syncing-a-fork/

git fetch upstream
git checkout master
git merge upstream/master
