--
-- PostgreSQL database cluster dump
--

\restrict 0fgAo0H71zOeMQ4ZpeDuyUrRVb3Ed5QpkjkTd4NuEiD2QN7Mcr03LXMlAVrCgiw

SET default_transaction_read_only = off;

SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;

--
-- Roles
--

CREATE ROLE ecoanp_user;
ALTER ROLE ecoanp_user WITH NOSUPERUSER INHERIT NOCREATEROLE NOCREATEDB LOGIN NOREPLICATION NOBYPASSRLS PASSWORD 'SCRAM-SHA-256$4096:jpZbsCo2vZtkf6yjLFAPkQ==$4fsYhrp7izA5oSMwW7qKYlhkZLQ9wS6mhRj4oV3wic4=:+uQ4xkgPEXtjmC4HEK4bYYvI1F4zl/dNVZ4bp8MjJVk=';
CREATE ROLE postgres;
ALTER ROLE postgres WITH SUPERUSER INHERIT CREATEROLE CREATEDB LOGIN REPLICATION BYPASSRLS PASSWORD 'SCRAM-SHA-256$4096:SKV9Q1YTLIgZ1s4wMissrg==$cxk/t2DGYQEyLSgEUdn8h9j1BwdMsYk0Vf1ZxEUPpTA=:JXKYh/axBjKF/Ei+gGcYY3uNLtsLiaauTq8hxvaVf0A=';

--
-- User Configurations
--








\unrestrict 0fgAo0H71zOeMQ4ZpeDuyUrRVb3Ed5QpkjkTd4NuEiD2QN7Mcr03LXMlAVrCgiw

--
-- PostgreSQL database cluster dump complete
--

