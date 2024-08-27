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

* Networking 
** Each subnet in a VPC has an associated route table. A subnet is considered public if routed to the internet via an internet gateway. 
each VPC belong to the region belonging to one or more available zone 
** Classless inter-domain Routing (CIDR): Notation for Describing blocks of IP addresses assigned in the vpc level
