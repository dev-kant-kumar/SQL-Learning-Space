create table users (
 _id int generated always as identity primary key,
 name varchar(100) not null,
 email varchar(100) unique not null , 
 password varchar(256) not null
);

insert into users (name , email , password) 
values
--('Dev Kant Kumar','eyemdev@gmail.com','87654wazxcvgy6543qRE');
('Sunil','sunil@gmail.com','9jh&^%$EDFGH'),
('Sarfraj','sarfraj@gmail.com','O*&^fr#WE%^&*IB');

select * from users;
select email from users;
select name from users where _id = 1;


insert into users(name , email , password) values ('Alex','alex@alex.com','alex123iuytr');
insert into users (name , email , password) values ('Brad','brad@gmail.com','brad@123I8d');

update users 
set email = 'alex@outlook.com'
where email = 'alex@alex.com'

select email from users where name = 'Brad';

update users
set 
 email = 'brad@brad.com',
 password = '567JUYTR4567HGRiuy'
where email = 'brad@gmail.com'

select * from users where email = 'brad@brad.com'

delete from users 
where email = 'brad@brad.com'

select * from users;
select count(*) from users;

