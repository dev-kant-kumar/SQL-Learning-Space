-- Day and Date : Friday 6 sept ,24
-- Practice session for internal exam 
-- Topics : 1 . DDL, DML and DQL Commands 

-- create table : Students ,Course and Enrollments
 
 CREATE TABLE Students(
 student_id Number(5) PRIMARY KEY,
 first_name varchar2(50) NOT NULL,
 last_name varchar2(50),
 birth_date DATE,
 email varchar(100) UNIQUE,
 enrollment_date DATE DEFAULT CURRENT_DATE);
 
 CREATE TABLE Courses(
 course_id Number(2) PRIMARY KEY,
 course_name varchar2(55) NOT NULL);
 
 CREATE TABLE Enrollments (
 enrollment_id Number(5) PRIMARY KEY,
 student_id Number(5),
 course_id Number(5),
 enrollment_date DATE,
 CONSTRAINT stu_id FOREIGN KEY(student_id) REFERENCES Students(student_id),
 CONSTRAINT cours_id FOREIGN KEY(course_id) REFERENCES Courses(Course_id));

CREATE TABLE customer(
customer_id Number(3) PRIMARY KEY,
customer_name varchar2(50) NOT NULL);

CREATE TABLE Sales(
customer_id Number(3),
order_id Number(5),
order_type varchar(20),
payment_mode varchar(50)
);

desc customer;

-- altering table

ALTER TABLE customer add phone_no number(10) unique ;
ALTER TABLE customer modify phone_no number(12);
ALTER TABLE customer rename column phone_no to phone_number;
ALTER TABLE customer drop column phone_number;

-- adding and removing primary key of customer
 --removing primary key
 ALTER TABLE customer drop primary key;
 
 -- adding primary key
 ALTER TABLE customer add primary key(customer_id);
 
 -- adding foreign key
 ALTER TABLE sales add constraint custm_id FOREIGN KEY(customer_id) REFERENCES customer(customer_id); 
 
 -- removing foreign key
 ALTER TABLE sales drop constraint custm_id;

-- rename table sales
ALTER TABLE sales rename to orders;

desc orders;

-- Drop commands
drop table students;
drop table courses;
drop table enrollments;

-- rename table
 RENAME Student TO students;


