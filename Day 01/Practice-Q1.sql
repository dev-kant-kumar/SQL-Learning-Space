-- create a database for your company xyz.
-- Create a table inside this DB to store employee info (id,name,salary)

CREATE DATABASE XYZ;
USE XYZ;

-- creating employee table in XYZ database
CREATE TABLE employee (Id INT PRIMARY KEY, Name VARCHAR (20) NOT NULL,Salary INT NOT NULL);

-- Command to see the schema of table created 
DESC employee;               -- show detailed information about table
SHOW CREATE TABLE employee;  -- show the command used to create table
SHOW COLUMNS FROM employee;  -- show detailed information about table

-- Inserting data into employee table inside XYZ database
INSERT INTO employee (Id,Name,Salary) VALUES 
(1,"Adam",25000),
(2,"Bob",30000),
(3, "Casey",40000);

-- selecting & viewing all employee table data
SELECT * FROM employee;