-- sample database
/* Create database college
create table student which have following details
rollno, name, marks, grade, city

have following data
101,Anil, 78, C, Pune
102, Bhumika, 93, A ,Mumbai
103, Chetan, 85, B ,Mumbai
104, Dhruv, 96, A, Delhi
105, Emanuel, 12, F, Delhi
106, Farah, 82, B, Delhi
*/

-- creating database college as college2
CREATE DATABASE college2;
USE college2;
DROP DATABASE college2; -- to drop this database if needed

-- creating table student
CREATE TABLE student (
Roll INT,
Name VARCHAR(30),
Marks INT,
Grade CHAR(1),
City VARCHAR(20),
PRIMARY KEY (Roll)
);

-- to see table structure
DESC student;
SHOW COLUMNS FROM student;
SHOW CREATE TABLE student; -- to see command used to create student table

-- inserting data into student table
INSERT INTO student(Roll,Name,Marks,Grade,City) VALUES 
 -- (101,'Anil', 78, 'C', 'Pune'),
(102,'Bhumika',93, 'A', 'Mumbai'),
(103,'Chetan',85,'B','Mumbai'),
(104,'Dhruv',96,'A','Delhi'),
(105,'Emanuel',12,'F','Delhi'),
(106,'Farah',82,'B','Delhi');


-- to check data of student table
SELECT * FROM student;
SELECT Name,Marks FROM student;
SELECT * FROM student WHERE marks>80;
SELECT * FROM student WHERE marks>80 AND City="Mumbai";
SELECT * FROM student WHERE marks>90 OR City="Mumbai";
SELECT * FROM student WHERE marks+10>100;
SELECT * FROM student WHERE city IN ("Mumbai","Gurgaon");
SELECT * FROM student WHERE city  NOT IN ("Mumbai","Gurgaon");
SELECT * FROM student WHERE Marks BETWEEN 80 AND 90;

-- to check top 3 student based on marks
SELECT * FROM student ORDER BY Marks DESC LIMIT 3;

-- to check top 3 student based on marks and city must be Mumbai
SELECT * FROM student WHERE City="Mumbai" ORDER BY Marks DESC LIMIT 3;
