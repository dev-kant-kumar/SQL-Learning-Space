-- command to open database created in previous session and named as sample database
SHOW DATABASES;
USE college2;

-- command to navigate to table inside college database
SHOW TABLES;

-- command to select records from student table
SELECT * FROM student ;

-- practicing today's learned topics with these commands
SELECT COUNT(Name) FROM student;
SELECT MAX(Marks) FROM student;
SELECT MIN(Marks) FROM student;
SELECT AVG(Marks) FROM student;

-- Practice Question 1: write the query to find avg marks in each city in ascending order
SELECT City, AVG(Marks) FROM student GROUP BY City ORDER BY AVG(Marks) ASC; 

-- Practice Question 2: For the given table , find the total payment to each payment method.

