# Create mysql stored procedure 
`create procedure employees.Getname()
select *
from employees;
;

create procedure employees.GetA()
select *
from employees
where first_name = 'Alain' and gender='M' and emp_no>=654161;`

## Populate mysql database.  

## Virtual Private Cloud (VPC)
* Your private cloud/network within the cloud
* Isolates your resources from everyone else's
