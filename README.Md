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

* Each subnet in a VPC has an associated route table. A subnet is considered public if routed to the internet via an internet gateway. 
each VPC belong to the region belonging to one or more available zone 

* Classless inter-domain Routing (CIDR): Notation for Describing blocks of IP addresses assigned in the vpc level

![https://www.youtube.com/watch?v=7_NNlnH7sAg](cidr.png)
In the diagram above, we have 6 EC2 instances, which will take up 6 IP addresses, if we add a database, they will need the IP address, so we have to make sure we have enough IP addresses for our VPC, for a given available IP address, we have to define a mask that will be us enough IP.
