# mysql

MySQL tips.

> More information you can found [here](https://www.tutorialspoint.com/mysql/mysql-drop-tables.htm)

## Connect

`mysql -u root --host myserver.com -p`

## CRUD

### Create

### Retrieve

### Update

```mysql
UPDATE glpi_users SET password=MD5('new_pass') WHERE name='admin';
```

### Delete

* Delete row

```mysql
DELETE FROM table_name [WHERE Clause]
```

* Drop table

```mysql
DROP TABLE table_name ;
```

## Permissions

* Show grants for current user

```mysql
SHOW GRANTS;
SHOW GRANTS FOR CURRENT_USER;
SHOW GRANTS FOR CURRENT_USER();
```

* Show all user privileges from information_schema


```mysql
use information_schema;
select * from USER_PRIVILEGES;
```

* Grant privileges

```mysql
use information_schema;
GRANT ALL PRIVILEGES ON `costs`.* TO 'aws_costs'@'1.1.1.1';
```

* Revoke privileges

```mysql
# TODO
```

## Admin

* Show table sizes

## Metrics

* Show main metrics

```mysql
select name,status,count,avg_count,max_count,subsystem from INNODB_METRICS;
```

* show System metrics

```mysql
select name,status,count,avg_count,max_count,subsystem from INNODB_METRICS where subsystem="os" or subsystem='file_system';
```

* Open files


```mysql
select * from global_status where VARIABLE_NAME='OPENED_FILES'
```

* Table sizes

```mysql
SELECT  table_schema as `Database`, table_name AS `Table`, round(((data_length + index_length) / 1024 / 1024), 2) `Size in MB` FROM information_schema.TABLES ORDER BY (data_length + index_length) DESC;
```

* proccess running (queries)

```mysql
show processlist;
```

```mysql
show full processlist;
```

* w/o sleeping queries

```mysql
SELECT * FROM INFORMATION_SCHEMA.PROCESSLIST WHERE COMMAND != 'Sleep';
```

* Kill queries running:

```mysql
kill <ID>;
```

* kill all queries

```
TODO
```


## GUI

### phpMySQLADmin

- Docker: https://hub.docker.com/r/phpmyadmin/phpmyadmin/

## References:

- https://dev.mysql.com/doc/mysql-getting-started/en/
