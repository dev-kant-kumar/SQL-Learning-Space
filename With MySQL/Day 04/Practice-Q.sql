-- Practice Question 2: For the given table , find the total payment to each payment method.
-- Table name : Payment
-- columns : customer_id,customer,mode,city
show databases;
create database if not exists sales;
use sales;
show tables;
desc payment;
select * from payment;

-- inserting data to payment table
insert into payment (customer_id,custoemr,mode,city) values (