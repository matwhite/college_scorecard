## College Scorecard Data
### Import Data Into MySQL

Working with the College Scorecard Data at <a
href="https://collegescorecard.ed.gov/data/">https://collegescorecard.ed.gov/data/</a>
is a lot easier when done using SQL to slice and dice the numbers or filter
records. Inside of <a href="/mysql_import">/mysql_import</a> you will find
the "build_database.pl" script to help you extract the data and dump it into a
MySQL database. This assumes you have access to the MySQL service and have
permissions to create tables and views within the database you are using.

* Step 0 - clone this repo

* Step 1 - edit your "config" file to match your database settings

    host - The server hosting MySQL

    db - The database where you will store the tables and view
    
    user - The MySQL username
    
    pass - The MySQL password
    
    prefix - This is helpful if you are trying many versions of the import and want to save them 

* Step 2 - download and extract the data dictionary and the source data from the College Scorecard Data site... 

    On Linux, that might look like:
    
    `cd mysql_import` 
    
    `wget https://collegescorecard.ed.gov/assets/CollegeScorecardDataDictionary-09-26-2016.xlsx`
    
    `wget https://ed-public-download.apps.cloud.gov/downloads/CollegeScorecard_Raw_Data.zip`
    
    `unzip CollegeScorecard_Raw_Data.zip`

* Step 3 - turn the data into an SQL file
    
    `./build_database.pl > raw_sql.sql`

* Step 4 - if everything looks OK, import it to your database
    
    `cat raw_sql.sql | mysql -hmyhostname -uuser -p dbname`

* Step 5 - run the verification script to ensure each field and row imported correctly
    
    `./verify_import.pl 2>&1 | tee log_verify`
    
    `grep -v '^GOT ROW' log_verify` (to see errors only)

* Step 6 - have fun doing data analysis using MySQL

The dataset isn't that large, but adding extra keys can be helpful as needed. Be
sure to check out the <a href="http://mysql.com">MySQL</a> site for full
documentation.

NOTE - These scripts assume you will run them where the data has been extracted,
and that the version of the data dictionary is consistent with the release from
2016-09-26. The college scorecard data is updated periodically, so this
underlying assumption may become invalid.

So far the only field differences I have found are due to UTF8 characters in
school and place names. That remains on my TODO list.
