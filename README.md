run on sql ->  
CREATE DATABASE gwa_db;  

USE gwa_db;  

CREATE TABLE subjects (  
    id INT AUTO_INCREMENT PRIMARY KEY,  
    name VARCHAR(100) NOT NULL,  
    units INT NOT NULL,  
    gwa FLOAT NOT NULL,  
    included BOOLEAN DEFAULT TRUE  
);  

make sure to set user and pass on the program  
life is better without pathfit
