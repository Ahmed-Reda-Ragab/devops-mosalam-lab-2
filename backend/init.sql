CREATE DATABASE IF NOT EXISTS appdb;
USE appdb;

CREATE TABLE IF NOT EXISTS tasks (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  description TEXT NULL,
  status ENUM('pending','completed') NOT NULL DEFAULT 'pending',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

INSERT INTO tasks (name, description, status) VALUES
('Buy groceries', 'Milk, eggs, bread, and coffee', 'pending'),
('Read project documentation', 'Review the requirements and design decisions', 'completed'),
('Update deployment scripts', 'Prepare Docker Compose and environment variables', 'pending'),
('Schedule team meeting', 'Book conference room for planning session', 'pending'),
('Clean workspace', 'Organize files and remove old containers', 'completed');
