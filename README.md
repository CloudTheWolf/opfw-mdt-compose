# Project EOL
The public version of this project has reached end of life and no further support for new deployments will be provided

## What does this mean??

You are free to download and run the MDT for your OPFW Server, however no support will be provided.
The docker images will remain available until Version 3.0

## Why the change?
The current version of the MDT is a hastle to setup and maintain, and I don't have as much time as I used to, so can't support new installs.
As such, I am "stepping away" from Version 2.x to focus on the new OP-MDT Project (Aka Version 3) which will be fully re-built from the ground
up to make it easier for you to deploy for your own server!

This includes cutting down from a 2 Service Deployment (Client and Server) to a single All In One package. 

## FAQ

- Q: Is there an ETA
  
  A: No ETA at this time
  
- Q: Will my old Data work on V3?

  A: Yes, Version 3 will work with Version 2.x Databases (Although some work will need to be done)

- Q: Will Version 3 remain Closed Source

  A: No, Version 3 will be Open Source. The only reason Version 2 was Closed Source was due to the previous developer having some Hard Coded values and the current project not working that well with using configurable values. V3 will have an entire config Overhaul with some dynamic config moving to be Database controlled.

- Q: What about the bots?

  A: For now the bots will remain as they are while I focus on the actual MDT. Once that is fully finished, the bots will be moved to the [Legacy-RP-Discord-Bots](https://github.com/CloudTheWolf/Legacy-RP-Discord-Bots) project, mirroring the bots made for DOC and BCDF

- Q: Anything else changing in Version 3.0?

  A: Yes, Version 3.0 aims to also include support for DOC,DOJ and EMS (And Maybe BCFD if they would like)
  This will allow for a fully integrated system between DOJ creating / maintaining the Penal Code, DOC handling extended sentencing etc, and EMS being able to fully integrate patiant data for a more in-depth Role Play experiance.

# How to install Legacy RP MDT

## Pre-Reqs: 
0: A domain name

1: A VPS running with at least 4GB RAM

2: 2 Discord Bots (One for PD called MDT Management, and one for EMS called EMS Management) 

3: 1 or more discord servers (For EMS and PD)

4: The following discord channels for PD
-	Roles Channel
-	Log Channel
-	Vote Channel
-	Time Channel 
-	Punishment Channel 

5: The following discord channels for EMS:
-	Time Checker Channel
-	Roles Channel

6: The Roles for PD (See here for example: https://github.com/CloudTheWolf/opfw-mdt-compose/blob/main/mdt/web/server/bot/roles/pdRoles.js )

7: The roles for EMS (See here for example: https://github.com/CloudTheWolf/opfw-mdt-compose/blob/main/mdt/web/server/bot/roles/emsRoles.js )

8: OPFW API Key


# Install 

0: In the DNS Settings for your domain, create 3 new A records for `mdt`, `pd-server`, and `whois` .

1: Install Docker, including the compose plugin (See here: https://docs.docker.com/engine/install/) 

2: Install Traefik (Replace mysite.com with your domain)
   Create a new directory called traefik and in that folder create a file called docker-compise.yml with the following: https://github.com/CloudTheWolf/opfw-mdt-compose/blob/main/traefik/docker-compose.yml  

3: Run the command `docker compose up -d`

4: Create 4 New Folders, one called mariadb and one called mdt-site, once called mdt-cache and once called mdt-bots

5: Create the file “/etc/mysql/conf.d/custom.cnf” with the contents from: https://github.com/CloudTheWolf/opfw-mdt-compose/blob/main/mariadb/etc/mysql/conf.d/custom.cnf 

6: In the mariadb folder created in Step 4, create a new file called docker-compose and put the following content: https://github.com/CloudTheWolf/opfw-mdt-compose/blob/main/mariadb/docker-compose.yml
   Make sure to update the `MARIADB_ROOT_PASSWORD` value

7: From the mariadb folder created in Step 4, run the command: `docker compose up -d`

8: Next create 2 new folders, one with the path /conf/mdt-client/helpers and the other with the path /conf/mdt-v2-server

9: In the server folder create a new file called .env and paste the contents from https://github.com/CloudTheWolf/opfw-mdt-compose/blob/main/mdt/web/server/.env.example into this file

10: Set all the values as required, leaving OPFW_HTTP_API and HTTPS_KEY as is. (See here to get FiveManage: [https://fivemanage.com/](https://fivemanage.com/) )

11: Now create a new file called pdRoles.js and paste the following contents: https://github.com/CloudTheWolf/opfw-mdt-compose/blob/main/mdt/web/server/bot/roles/pdRoles.js then configure with the roles you need. 

12: Now create a new file called emsRoles.js and paste the following contents: https://github.com/CloudTheWolf/opfw-mdt-compose/blob/main/mdt/web/server/bot/roles/emsRoles.js   then configure with the roles you need.

13: Now, client/helpers folder create a new file called backend.js and paste the content of https://github.com/CloudTheWolf/opfw-mdt-compose/blob/main/mdt/web/client/backend.js (replacing mysite.com with your site FQDN address, eg legacyrp.company) 

14: Going back to the mdt-site folder create a new file called docker-compose.yml and paste the contents of https://github.com/CloudTheWolf/opfw-mdt-compose/blob/main/mdt/web/docker-compose.yml then replace mysite.com with your FQDN on lines 20 and 45

15: Run the following commands:
 chmod 666 /conf/mdt-v2-server/prod.env 

16: Next, run the command `docker login https://repo.legacyrp.company` and enter the username and password ( `legacy` for both user and pass) 

17: Once done, make sure you are still in the mdt-site folder and run the command `docker compose up -d`

18: Next create the directory /var/www/html/op-framework and chmod it to 777

19: Download the latest version of the Cache Sync Tool https://github.com/CloudTheWolf/Legacy-API-Cache-Sync and put into /opt/bots/opfwsync/

20: Edit the appsettings.json and set the apiBaseUrl, apiKey, and mysql details

21: Install the dotnet 6 and dotnet 8 runtimes (See instructions here: https://learn.microsoft.com/en-us/dotnet/core/install/linux-debian ) (Both are needed)

22: Run the command crontab -e, and if prompted, select the nano option, then paste the following
```
* * * * * cp /opt/bots/opfwsync/temp/c3/*.json /var/www/html/op-framework/  > /dev/null 2>&1 
 */5 * * * * cd /opt/bots/opfwsync && dotnet /opt/bots/opfwsync/Legacy-API-Cache-Sync.dll >> /var/log/sync.log
```
23: Go to the mdt-cache folder created in step 4 and create a file called docker-compose.yml, then paste the contents of https://github.com/CloudTheWolf/opfw-mdt-compose/blob/main/http/docker-compose.yml 

24: Run the command `docker compose up -d`

25: Go to the mdt-bots folder created in step 4 and create a file called docker-compose.yml, then paste in contents from https://github.com/CloudTheWolf/opfw-mdt-compose/blob/main/mdt/bot/docker-compose.yml 

26: Run the command `docker compose up -d`

27: If all is done correctly the bots should be Online and the MDT should be accessible.

28: Using the latest DB Schema ([HERE](https://github.com/CloudTheWolf/opfw-mdt-compose/blob/main/mdt/web/server/db_schema.sql)) import the schema using either MySql Workbench Or another tool. Then go to the login table and create a new row with your CID, put the password as zzz and the reset_passphrase as changeme then set the date to some random future date. 

29: Now go to the login page of the mdt and click forgotten password, enter your CID and the code you set in step 25, then enter your new password of choice and you should now be good to login!
