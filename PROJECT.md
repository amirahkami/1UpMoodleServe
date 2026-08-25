- What ever you do, do it your heart and brain together.

## Project Description

The goal of this project focued on spin up a production grade Moodle server on a virtual machine or equivalent environment. The entire operation will carry on smoothly within minutes. The need is to make moodle really online for small universites. It needs also use Identity Manager for moodle. we will use Keycloak however we will document the techstack in another md file.

the initial idea of entire workflow looks as following:
1. On Digital Ocean or anywhere else we create a droplet or VPS, actually it does not matter where
2. a provisioning script installs all dependencies, update server and prepare the environment for real deployment and also another test scripts should check if every needs are up and run, some services need restart after installation for example. database and keycloak should created.
3. a hardening script should harden the server against threads, and secure firewalls, also we prefer change some critical ports like 22. hardening script should make it secure
4. then we need database and keycloak realm
5. moodle deployment
6. installing a moodle plugin we developed. this plugin sends http requests to another server on another university over internet, so it is important moodle send http request to another API at another university
7. 3 moodle courses
8. 
