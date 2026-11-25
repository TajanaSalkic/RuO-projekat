-- seed.sql — demo podaci. Idempotentno: ON CONFLICT DO NOTHING.
-- Heš lozinke = Base64(SHA256(lozinka)) — identično backendu (Register/Login.Handler.cs).
-- Demo lozinke: admin=Admin123!, mentori=Mentor123!, studenti=Student123!
-- Svi korisnici Approved=true (login provjerava Approved).

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Uloge
INSERT INTO "Roles" ("Id","Name") VALUES
  (1,'Admin'),(2,'Mentor'),(3,'Student')
ON CONFLICT ("Id") DO NOTHING;

-- Korisnici
INSERT INTO "Users" ("Id","Name","Surname","Email","Password","Role_Id","Approved") VALUES
  (1,'Admin','Admin',     'admin@ruo.lab',    encode(digest('Admin123!','sha256'),'base64'),   1, true),
  (2,'Amina','Mentorovic','mentor1@ruo.lab',  encode(digest('Mentor123!','sha256'),'base64'),  2, true),
  (3,'Benjamin','Mentoric','mentor2@ruo.lab', encode(digest('Mentor123!','sha256'),'base64'),  2, true),
  (4,'Dalila','Studentic', 'student1@ruo.lab', encode(digest('Student123!','sha256'),'base64'), 3, true),
  (5,'Emir','Hodzic',      'student2@ruo.lab', encode(digest('Student123!','sha256'),'base64'), 3, true),
  (6,'Faris','Kovac',      'student3@ruo.lab', encode(digest('Student123!','sha256'),'base64'), 3, true),
  (7,'Lejla','Begic',      'student4@ruo.lab', encode(digest('Student123!','sha256'),'base64'), 3, true),
  (8,'Nedim','Alic',       'student5@ruo.lab', encode(digest('Student123!','sha256'),'base64'), 3, true),
  (9,'Sara','Music',       'student6@ruo.lab', encode(digest('Student123!','sha256'),'base64'), 3, true)
ON CONFLICT ("Id") DO NOTHING;

-- Projekti
INSERT INTO "Projects" ("Id","Title","Description","StartDate","EndDate","Status","Points","Url") VALUES
  (1,'Cloud infrastruktura','Troslojna aplikacija kao kod', NOW(), NOW() + interval '30 days', 0, 100, NULL),
  (2,'Web aplikacija','Angular + .NET + PostgreSQL',        NOW(), NOW() + interval '60 days', 0,  80, NULL)
ON CONFLICT ("Id") DO NOTHING;

-- Zadaci
INSERT INTO "Tasks" ("Id","Title","Description","StartDate","EndDate","Status","Points") VALUES
  (1,'Terraform VM-ovi','Kreirati virtuelne mašine', NOW(), NOW() + interval '7 days', 0, 10),
  (2,'Ansible role','common/docker/firewall',        NOW(), NOW() + interval '7 days', 0, 10),
  (3,'DNS','BIND9 + Terraform zapisi',                NOW(), NOW() + interval '7 days', 0, 10)
ON CONFLICT ("Id") DO NOTHING;

-- Veze zadatak–projekat–korisnik (Creator=true za mentora–vlasnika projekta)
INSERT INTO "Task_Projects" ("Id","User_ID","Task_ID","Project_ID","Creator") VALUES
  (1,2,NULL,1,true),   -- mentor1 vlasnik projekta 1
  (2,4,1,1,false),     -- student1 -> task1
  (3,5,2,1,false),     -- student2 -> task2
  (4,6,3,1,false),     -- student3 -> task3
  (5,3,NULL,2,true)    -- mentor2 vlasnik projekta 2
ON CONFLICT ("Id") DO NOTHING;

-- Mentor–student veze
INSERT INTO "Mentor_Students" ("Id","Mentor_ID","Student_ID","AssignedDate","UserId") VALUES
  (1,2,4,NOW(),NULL),(2,2,5,NOW(),NULL),(3,2,6,NOW(),NULL),
  (4,3,7,NOW(),NULL),(5,3,8,NOW(),NULL)
ON CONFLICT ("Id") DO NOTHING;

-- Komentari
INSERT INTO "Comments" ("Id","Content","CreatedDate","TaskId","UserId") VALUES
  (1,'Odličan napredak na Terraform dijelu.', NOW(), 1, 2),
  (2,'Hvala, nastavljam s Ansible rolama.',   NOW(), 1, 4)
ON CONFLICT ("Id") DO NOTHING;

-- Poravnaj identity sekvence da aplikacija ne kolidira sa seed Id-evima
SELECT setval(pg_get_serial_sequence('"Roles"','Id'),           (SELECT MAX("Id") FROM "Roles"));
SELECT setval(pg_get_serial_sequence('"Users"','Id'),           (SELECT MAX("Id") FROM "Users"));
SELECT setval(pg_get_serial_sequence('"Projects"','Id'),        (SELECT MAX("Id") FROM "Projects"));
SELECT setval(pg_get_serial_sequence('"Tasks"','Id'),           (SELECT MAX("Id") FROM "Tasks"));
SELECT setval(pg_get_serial_sequence('"Task_Projects"','Id'),   (SELECT MAX("Id") FROM "Task_Projects"));
SELECT setval(pg_get_serial_sequence('"Mentor_Students"','Id'), (SELECT MAX("Id") FROM "Mentor_Students"));
SELECT setval(pg_get_serial_sequence('"Comments"','Id'),        (SELECT MAX("Id") FROM "Comments"));
