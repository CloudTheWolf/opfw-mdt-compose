-- phpMyAdmin SQL Dump
-- version 5.2.2
-- https://www.phpmyadmin.net/
--
-- Host: mariadb
-- Generation Time: May 28, 2025 at 07:01 AM
-- Server version: 11.3.2-MariaDB-1:11.3.2+maria~ubu2204
-- PHP Version: 8.2.27

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Database: `legacymdt`
--
CREATE DATABASE IF NOT EXISTS `legacymdt` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE `legacymdt`;

DELIMITER $$
--
-- Procedures
--
CREATE PROCEDURE `DeleteIncidentEvidence` (IN `input_evidence_id` INT, IN `input_officer_id` INT)   BEGIN
    DECLARE incidentId INT;

    -- Retrieve the incident_id associated with the evidence_id
    SELECT incident_id INTO incidentId
    FROM incident_evidence
    WHERE evidence_id = input_evidence_id
    LIMIT 1;

    -- Insert log into the logs table
    INSERT INTO logs (data, note, timestamp, loggedBy)
    VALUES (CONCAT('evidence_id ', input_evidence_id, ' deleted from incident_id ', incidentId),
            'evidence_deleted',
            UTC_TIMESTAMP(),
            input_officer_id);

    -- Delete the evidence from incident_evidence
    DELETE FROM incident_evidence 
    WHERE evidence_id = input_evidence_id;
END$$

CREATE PROCEDURE `InsertOrUpdateCharacter` (IN `character_json` LONGTEXT)   BEGIN

    INSERT INTO `characters` (`character_id`, `first_name`, `last_name`, `gender`, `job_name`, `department_name`, `position_name`, `date_of_birth`, `phone_number`,`license_identifier`,`mugshot`)
    SELECT d.character_id, d.first_name, d.last_name, d.gender, d.job_name, d.department_name, d.position_name, d.date_of_birth, d.phone_number, d.license_identifier, d.mugshot
    FROM JSON_TABLE(character_json, '$.data[*]' COLUMNS (
        character_id INT PATH '$.character_id',
        first_name TEXT PATH '$.first_name',
        last_name TEXT PATH '$.last_name',
        gender INT PATH '$.gender',
        job_name TEXT PATH '$.job_name',
        department_name TEXT PATH '$.department_name',
        position_name TEXT PATH '$.position_name',
        date_of_birth DATE PATH '$.date_of_birth',
        phone_number TEXT PATH '$.phone_number',
        license_identifier TEXT PATH '$.license_identifier',
        mugshot TEXT PATH '$.mugshot_url'
    )) AS d
    ON DUPLICATE KEY UPDATE
        `first_name` = VALUES(`first_name`),
        `last_name` = VALUES(`last_name`),
        `job_name` = VALUES(`job_name`),
        `department_name` = VALUES(`department_name`),
        `position_name` = VALUES(`position_name`),
        `phone_number` = VALUES(`phone_number`),
        `mugshot` = VALUES(`mugshot`);

    SET @v_character_id = JSON_EXTRACT(character_json, '$.character_id');
    SET @v_on_duty_time = JSON_UNQUOTE(JSON_EXTRACT(character_json, '$.on_duty_time."Law Enforcement"'));

    IF @v_on_duty_time IS NOT NULL AND @v_on_duty_time <> '' THEN
      -- Insert or update the record in the `time` table
      INSERT INTO `time` (`character_id`, `on_duty_time`)
      VALUES (@v_character_id, @v_on_duty_time)
      ON DUPLICATE KEY UPDATE
          `on_duty_time` = VALUES(`on_duty_time`);
    END IF;


END$$

CREATE PROCEDURE `InsertOrUpdateCharacterVehicleFinance` (IN `finance_json` LONGTEXT)   BEGIN
    -- Insert or update into character_vehicle_finance table
    INSERT INTO `character_vehicle_finance` (`owner_cid`, `plate`)
    SELECT d.owner_cid, d.plate
    FROM JSON_TABLE(finance_json, '$.data[*]' COLUMNS (
        owner_cid INT PATH '$.owner_cid',
        plate TEXT PATH '$.plate'
    )) AS d
    ON DUPLICATE KEY UPDATE
        `owner_cid` = VALUES(`owner_cid`),
        `plate` = VALUES(`plate`);

    -- Update the character_vehicles table
    -- Note: Use JSON_TABLE to extract all plates from the JSON array
    UPDATE character_vehicles cv
    JOIN (
        SELECT plate
        FROM JSON_TABLE(finance_json, '$.data[*]' COLUMNS (
            plate TEXT PATH '$.plate'
        )) AS jp
    ) AS j ON cv.plate = j.plate
    SET cv.financed = 1;
END$$

CREATE PROCEDURE `InsertOrUpdateCharacterVehicles` (IN `vehicle_json` LONGTEXT)   BEGIN

    INSERT INTO `character_vehicles` (`vehicle_id`, `owner_cid`, `name`, `plate`, `photo`, `added_by`, `added_date_time`)
    SELECT 
        d.vehicle_id, 
        d.owner_cid, 
        d.model_name, 
        d.plate, 
        NULL as photo, 
        0 as added_by, 
        UTC_TIMESTAMP() as added_date_time
    FROM 
        JSON_TABLE(vehicle_json, '$.data[*]' COLUMNS (
            vehicle_id INT PATH '$.vehicle_id',
            owner_cid INT PATH '$.owner_cid',
            model_name TEXT PATH '$.model_name',
            plate TEXT PATH '$.plate',
            was_boosted INT PATH '$.was_boosted'
        )) AS d
	WHERE d.was_boosted = 0
    ON DUPLICATE KEY UPDATE
        `owner_cid` = VALUES(`owner_cid`),
        `plate` = VALUES(`plate`),
        `added_by` = VALUES(`added_by`),
        `added_date_time` = VALUES(`added_date_time`);

END$$

DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `announcements`
--

CREATE TABLE `announcements` (
  `announcement_id` int(11) NOT NULL,
  `type` varchar(50) DEFAULT NULL,
  `announcement` longtext NOT NULL,
  `added_by` int(11) NOT NULL,
  `added_date_time` datetime NOT NULL,
  `expire_on` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `api_keys`
--

CREATE TABLE `api_keys` (
  `id` int(11) NOT NULL,
  `api_key` varchar(255) NOT NULL,
  `is_active` tinyint(1) DEFAULT 1,
  `description` varchar(255) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `changes`
--

CREATE TABLE `changes` (
  `id` bigint(20) NOT NULL,
  `affected_table` varchar(64) DEFAULT NULL,
  `change_type` enum('INSERT','UPDATE','DELETE') DEFAULT NULL,
  `old_data_json` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`old_data_json`)),
  `new_data_json` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`new_data_json`)),
  `change_timestamp` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `characters`
--

CREATE TABLE `characters` (
  `character_id` int(11) NOT NULL,
  `first_name` longtext CHARACTER SET utf8mb3 COLLATE utf8mb3_unicode_ci DEFAULT NULL,
  `last_name` longtext DEFAULT NULL,
  `gender` int(11) DEFAULT NULL,
  `job_name` longtext CHARACTER SET utf8mb3 COLLATE utf8mb3_unicode_ci DEFAULT NULL,
  `department_name` longtext CHARACTER SET utf8mb3 COLLATE utf8mb3_unicode_ci DEFAULT NULL,
  `position_name` longtext CHARACTER SET utf8mb3 COLLATE utf8mb3_unicode_ci DEFAULT NULL,
  `date_of_birth` longtext CHARACTER SET utf8mb3 COLLATE utf8mb3_unicode_ci DEFAULT NULL,
  `phone_number` longtext CHARACTER SET utf8mb3 COLLATE utf8mb3_unicode_ci DEFAULT NULL,
  `license_identifier` longtext CHARACTER SET utf8mb3 COLLATE utf8mb3_unicode_ci DEFAULT NULL,
  `mugshot` longtext CHARACTER SET utf8mb3 COLLATE utf8mb3_unicode_ci DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `character_expungements`
--

CREATE TABLE `character_expungements` (
  `expungement_id` int(11) NOT NULL,
  `character_id` int(11) NOT NULL,
  `expungement_note` longtext DEFAULT NULL,
  `expungement_date` datetime NOT NULL,
  `added_by` int(11) NOT NULL,
  `added_date_time` datetime NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `character_notes`
--

CREATE TABLE `character_notes` (
  `note_id` int(11) NOT NULL,
  `character_id` int(11) NOT NULL,
  `character_note` longtext NOT NULL,
  `type` varchar(50) DEFAULT 'general',
  `added_by` int(11) NOT NULL,
  `added_date_time` datetime NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `character_pictures`
--

CREATE TABLE `character_pictures` (
  `picture_id` int(11) NOT NULL,
  `character_id` int(11) NOT NULL,
  `character_picture_url` longtext NOT NULL,
  `added_by` int(11) NOT NULL,
  `added_date_time` datetime NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `character_points`
--

CREATE TABLE `character_points` (
  `reset_id` int(11) NOT NULL,
  `character_id` int(11) NOT NULL,
  `reset_date` datetime NOT NULL,
  `added_by` int(11) NOT NULL,
  `added_date_time` datetime NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci ROW_FORMAT=DYNAMIC;

-- --------------------------------------------------------

--
-- Table structure for table `character_properties`
--

CREATE TABLE `character_properties` (
  `property_id` int(11) NOT NULL,
  `character_id` int(11) DEFAULT NULL,
  `address` varchar(100) DEFAULT NULL,
  `added_by` int(11) DEFAULT NULL,
  `added_date_time` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `character_tags`
--

CREATE TABLE `character_tags` (
  `tag_id` int(10) UNSIGNED NOT NULL,
  `character_id` int(11) DEFAULT NULL,
  `value` longtext NOT NULL,
  `background_color` varchar(50) NOT NULL DEFAULT '',
  `text_color` varchar(50) NOT NULL,
  `added_by` int(11) DEFAULT NULL,
  `added_date_time` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `character_vehicles`
--

CREATE TABLE `character_vehicles` (
  `vehicle_id` int(11) NOT NULL,
  `owner_cid` int(11) NOT NULL DEFAULT 0,
  `name` varchar(100) NOT NULL DEFAULT '',
  `plate` varchar(50) NOT NULL DEFAULT '',
  `photo` longtext DEFAULT NULL,
  `added_by` int(11) DEFAULT NULL,
  `added_date_time` datetime DEFAULT NULL,
  `financed` varchar(45) NOT NULL DEFAULT '0',
  `repossessed` int(11) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `character_vehicle_finance`
--

CREATE TABLE `character_vehicle_finance` (
  `finance_id` int(11) NOT NULL,
  `owner_cid` int(11) NOT NULL,
  `plate` varchar(45) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `character_warrants_bolos`
--

CREATE TABLE `character_warrants_bolos` (
  `id` int(11) NOT NULL,
  `character_id` int(11) NOT NULL,
  `officer_id` int(11) NOT NULL,
  `details` longtext DEFAULT NULL,
  `served` int(11) DEFAULT 0,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `demotions`
--

CREATE TABLE `demotions` (
  `demotions_id` int(11) NOT NULL,
  `week_number` int(11) NOT NULL,
  `demotion_for` int(11) NOT NULL,
  `demotion_by` int(11) NOT NULL,
  `reasoning` longtext NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `incidents`
--

CREATE TABLE `incidents` (
  `incident_id` int(11) NOT NULL,
  `title` varchar(100) NOT NULL,
  `type` varchar(100) NOT NULL,
  `location` varchar(100) NOT NULL,
  `created_by` int(11) DEFAULT NULL,
  `created_date_time` datetime DEFAULT NULL,
  `updated_by` int(11) DEFAULT NULL,
  `updated_date_time` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `incident_arrests`
--

CREATE TABLE `incident_arrests` (
  `arrest_id` int(11) NOT NULL,
  `incident_id` int(11) NOT NULL DEFAULT 0,
  `character_id` int(11) NOT NULL,
  `time` int(11) DEFAULT NULL,
  `fine` int(11) DEFAULT NULL,
  `plea` varchar(50) DEFAULT NULL,
  `items_returned` tinyint(1) NOT NULL DEFAULT 0,
  `items_returned_by` int(11) DEFAULT NULL,
  `items_returned_date_time` datetime DEFAULT NULL,
  `arrested_by` int(11) DEFAULT NULL,
  `arrested_date_time` datetime DEFAULT NULL,
  `processed_by` int(11) DEFAULT NULL,
  `processed_date_time` datetime DEFAULT NULL,
  `sealed` tinyint(1) NOT NULL DEFAULT 0,
  `sealed_by` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `incident_arrests_charges`
--

CREATE TABLE `incident_arrests_charges` (
  `charge_id` int(11) NOT NULL,
  `penal_code_charge_id` int(11) DEFAULT NULL,
  `arrest_id` int(11) NOT NULL DEFAULT 0,
  `enhancements` varchar(100) DEFAULT NULL,
  `counts` int(11) DEFAULT NULL,
  `added_by` int(11) DEFAULT NULL,
  `added_date_time` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `incident_arrests_items`
--

CREATE TABLE `incident_arrests_items` (
  `item_id` int(11) NOT NULL,
  `arrest_id` int(11) NOT NULL DEFAULT 0,
  `type` varchar(50) NOT NULL DEFAULT '0',
  `item` longtext NOT NULL,
  `added_by` int(11) NOT NULL DEFAULT 0,
  `added_date_time` datetime NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `incident_arrests_mugshots`
--

CREATE TABLE `incident_arrests_mugshots` (
  `mugshot_id` int(11) NOT NULL,
  `arrest_id` int(11) NOT NULL,
  `mugshot_title` longtext NOT NULL,
  `mugshot_url` longtext NOT NULL,
  `added_by` int(11) NOT NULL,
  `added_by_date_time` datetime NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `incident_evidence`
--

CREATE TABLE `incident_evidence` (
  `evidence_id` int(11) NOT NULL,
  `incident_id` int(11) NOT NULL DEFAULT 0,
  `type` varchar(50) NOT NULL DEFAULT '0',
  `evidence` longtext NOT NULL,
  `added_by` int(11) NOT NULL DEFAULT 0,
  `added_date_time` datetime NOT NULL DEFAULT '0000-00-00 00:00:00'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `incident_officers`
--

CREATE TABLE `incident_officers` (
  `officers_id` int(11) NOT NULL,
  `incident_id` int(11) NOT NULL,
  `character_id` int(11) NOT NULL,
  `added_by` int(11) NOT NULL,
  `added_date_time` datetime NOT NULL,
  `was_injured` tinyint(1) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `incident_persons`
--

CREATE TABLE `incident_persons` (
  `persons_id` int(10) UNSIGNED NOT NULL,
  `incident_id` int(11) NOT NULL,
  `character_id` int(11) NOT NULL,
  `phone_number` varchar(20) DEFAULT NULL,
  `type` varchar(20) DEFAULT NULL,
  `added_by` int(11) DEFAULT NULL,
  `added_date_time` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `incident_reports`
--

CREATE TABLE `incident_reports` (
  `report_id` int(11) NOT NULL,
  `incident_id` int(11) NOT NULL,
  `type` varchar(50) DEFAULT NULL,
  `report` longtext NOT NULL,
  `added_by` int(11) NOT NULL,
  `added_date_time` datetime NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `incident_tags`
--

CREATE TABLE `incident_tags` (
  `tag_id` int(10) UNSIGNED NOT NULL,
  `incident_id` int(11) DEFAULT 0,
  `value` longtext NOT NULL,
  `background_color` varchar(50) NOT NULL DEFAULT '',
  `text_color` varchar(50) NOT NULL DEFAULT '',
  `added_by` int(11) DEFAULT 0,
  `added_date_time` datetime DEFAULT '0000-00-00 00:00:00'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `items`
--

CREATE TABLE `items` (
  `name` varchar(100) NOT NULL DEFAULT 'item',
  `label` varchar(100) DEFAULT NULL,
  `is_weapon` tinyint(1) DEFAULT 0,
  `is_drug` tinyint(1) DEFAULT 0,
  `is_food` tinyint(1) DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

--
-- Dumping data for table `items`
--

INSERT INTO `items` (`name`, `label`, `is_weapon`, `is_drug`, `is_food`) VALUES
('absinthe', 'Absinthe', 0, 0, 1),
('acetone', 'Acetone', 0, 0, 0),
('acid', 'Acid (LSD)', 0, 1, 0),
('advanced_lockpick', 'Advanced Lockpick', 0, 0, 0),
('advanced_repair_kit', 'Advanced Repair Kit', 0, 0, 0),
('almond_joy', 'Almond Joy', 0, 0, 1),
('almond_milk', 'Almond Milk', 0, 0, 1),
('aluminium', 'Crude Aluminium', 0, 0, 0),
('aluminium_ore', 'Aluminium Ore', 0, 0, 0),
('aluminium_plate', 'Aluminium Plate', 0, 0, 0),
('aluminium_powder', 'Aluminium Powder', 0, 0, 0),
('aluminium_rod', 'Aluminium Rod', 0, 0, 0),
('ammo_box', 'Big Ammo Box', 0, 0, 0),
('ammonia', 'Ammonia', 0, 0, 0),
('ancient_coin', 'Ancient Coin', 0, 0, 0),
('ancient_ring', 'Ancient Ring', 0, 0, 0),
('antenna', 'Antenna', 0, 0, 0),
('antibiotics', 'Antibiotics', 0, 1, 0),
('antlers', 'Deer Antlers', 0, 0, 0),
('apple', 'Apple', 0, 0, 1),
('apple_juice', 'Apple Juice', 0, 0, 1),
('arena_pill', 'Arena Pill', 0, 0, 0),
('asahi_beer', 'Asahi Beer', 0, 0, 1),
('avocado', 'Avocado', 0, 0, 0),
('avocado_smoothie', 'Avocado Smoothie', 0, 0, 1),
('bacon_burger', 'Bacon- Cheeseburger', 0, 0, 1),
('baking_soda', 'Baking Soda', 0, 0, 0),
('ballistic_shield', 'Ballistic Shield', 0, 0, 0),
('banana', 'Banana', 0, 0, 1),
('banana_peel', 'Banana Peel', 0, 0, 0),
('bandages', 'Bandages', 0, 0, 0),
('bandana', 'Bandana', 0, 0, 0),
('bandit_1', 'Bandit 1', 0, 0, 0),
('bandit_2', 'Bandit 2', 0, 0, 0),
('bank_rockfish', 'Bank Rockfish', 0, 0, 0),
('bar_license', 'Bar/Law License', 0, 0, 0),
('barrier', 'Barrier', 0, 0, 0),
('basic_lockpick', 'Basic Lockpick', 0, 0, 0),
('basic_repair_kit', 'Basic Repair Kit', 0, 0, 0),
('battering_ram', 'Battering Ram', 0, 0, 0),
('battery_pack', 'Battery Pack', 0, 0, 0),
('bbq_sandwich', 'BBQ Sandwich', 0, 0, 1),
('bbq_sauce', 'BBQ Sauce', 0, 0, 1),
('bcfd_badge', 'BCFD', 0, 0, 0),
('bcso_badge', 'BCSO Badge', 0, 0, 0),
('beach_chair', 'Beach Chair', 0, 0, 0),
('bean_coffee', 'Bean Coffee', 0, 0, 1),
('bean_machine_delivery', 'Bean Machine Delivery', 0, 0, 0),
('beans', 'Beans', 0, 0, 1),
('beans_toast', 'Beans on Toast', 0, 0, 1),
('bear_trap', 'Bear Trap', 0, 0, 0),
('beef_jerky', 'Beef Jerky', 0, 0, 1),
('beef_sausages', 'Beef Sausages', 0, 0, 0),
('beer', 'Beer', 0, 0, 1),
('belgian_fries', 'Belgian Fries', 0, 0, 1),
('bell_pepper', 'Bell Pepper', 0, 0, 1),
('bell_pepper_sliced', 'Sliced Bell Pepper', 0, 0, 1),
('bento_box', 'Bento Box', 0, 0, 1),
('berry_cake', 'Berry Cake', 0, 0, 1),
('berry_cake_slice', 'Berry Cake Slice', 0, 0, 1),
('big_tv', 'Big TV', 0, 0, 0),
('binoculars', 'Binoculars', 0, 0, 0),
('black_and_yellow_rockfish', 'Black and Yellow Rockfish', 0, 0, 0),
('black_dildo', 'Black Dildo', 0, 0, 0),
('black_olives', 'Black Olives', 0, 0, 1),
('black_parachute', 'Black Parachute', 1, 0, 0),
('black_rockfish', 'Black Rockfish', 0, 0, 0),
('blackgill_rockfish', 'Blackgill Rockfish', 0, 0, 0),
('blackspotted_rockfish', 'Blackspotted Rockfish', 0, 0, 0),
('bleach', 'Bleach', 0, 0, 0),
('blender', 'Blender', 0, 0, 0),
('blue_fishing_chair', 'Blue Fishing Chair', 0, 0, 0),
('blue_hiking_backpack', 'Blue Hiking Backpack', 0, 0, 0),
('blue_parachute', 'Blue Parachute', 1, 0, 0),
('blue_rockfish', 'Blue Rockfish', 0, 0, 0),
('bne_burger', 'Bacon n\' Egg Burger', 0, 0, 1),
('boat_license', 'Boating License', 0, 0, 0),
('bocaccio', 'Bocaccio', 0, 0, 0),
('body_armor', 'Body Armor', 0, 0, 0),
('bolt_cutter', 'Bolt Cutter', 0, 0, 0),
('bong', 'Bong', 0, 0, 0),
('bong_water', 'Bong Water', 0, 0, 0),
('boombox', 'Boombox', 0, 0, 0),
('boosting_tablet', 'Boosting Tablet', 0, 0, 0),
('boxing_gloves', 'Boxing Gloves', 0, 0, 0),
('brass', 'Brass', 0, 0, 0),
('bread_loaf', 'Bread Loaf', 0, 0, 0),
('bread_sticks', 'Bread Sticks', 0, 0, 1),
('breadcrumbs', 'Breadcrumbs', 0, 0, 1),
('brochure', 'Brochure', 0, 0, 0),
('bronzespotted_rockfish', 'Bronzespotted Rockfish', 0, 0, 0),
('brown_rockfish', 'Brown Rockfish', 0, 0, 0),
('brownies', 'Brownies', 0, 0, 1),
('bucket', 'Bucket', 0, 0, 0),
('bumps_sign', 'Bumps Sign', 0, 0, 0),
('burger_buns', 'Burger Buns', 0, 0, 0),
('burger_shot_delivery', 'Burger Shot Meal', 0, 0, 0),
('burnt_meat', 'Burnt Meat', 0, 0, 1),
('burrito', 'Burrito', 0, 0, 1),
('bus_map', 'Bus Map', 0, 0, 0),
('bus_ticket', 'Bus Ticket', 0, 0, 0),
('cabbage', 'Cabbage', 0, 0, 0),
('cabbage_seeds', 'Cabbage Seeds', 0, 0, 0),
('cabezon', 'Cabezon', 0, 0, 0),
('calico_rockfish', 'Calico Rockfish', 0, 0, 0),
('california_scorpionfish', 'California Scorpionfish', 0, 0, 0),
('campfire', 'Campfire', 0, 0, 0),
('canary_rockfish_variant_1', 'Canary Rockfish (Variant 1)', 0, 0, 0),
('canary_rockfish_variant_2', 'Canary Rockfish (Variant 2)', 0, 0, 0),
('canine_tooth', 'Mountain Lion Tooth', 0, 0, 0),
('canvas_tent', 'Canvas Tent', 0, 0, 0),
('cappuccino', 'Cappuccino', 0, 0, 1),
('capri_sun', 'Capri Sun', 0, 0, 1),
('car_brakes', 'Brakes', 0, 0, 0),
('car_keys', 'Car Keys', 0, 0, 0),
('car_radiator', 'Radiator', 0, 0, 0),
('card_paper', 'Card Paper (9x5)', 0, 0, 0),
('carrot', 'Carrot', 0, 0, 1),
('casing', 'Casing', 0, 0, 0),
('cat_0', 'Tabby Cat', 0, 0, 0),
('cat_1', 'Black Cat', 0, 0, 0),
('cat_2', 'Brown Cat', 0, 0, 0),
('cat_food', 'Cat Food', 0, 0, 1),
('cat_treats', 'Cat Treats', 0, 0, 1),
('catalytic_converter', 'Catalytic Converter', 0, 0, 0),
('caterpillar', 'Caterpillar', 0, 0, 0),
('cent_1', 'Penny', 0, 0, 0),
('cent_10', 'Dime', 0, 0, 0),
('cent_25', 'Quarter', 0, 0, 0),
('cent_5', 'Nickel', 0, 0, 0),
('cent_50', 'Half Dollar', 0, 0, 0),
('charcoal', 'Charcoal', 0, 0, 0),
('cheese', 'Cheese', 0, 0, 0),
('cheeseburger', 'Cheeseburger', 0, 0, 1),
('cheesecake', 'Cheesecake', 0, 0, 1),
('cheetos', 'Cheetos', 0, 0, 1),
('cherry', 'Cherry', 0, 0, 1),
('chicken_breast', 'Chicken Breast', 0, 0, 1),
('chicken_nuggets', 'Chicken Nuggets', 0, 0, 1),
('chicken_nuggets_raw', 'Raw Chicken Nuggets', 0, 0, 1),
('chili', 'Chili Peppers', 0, 0, 1),
('chilipepper_rockfish', 'Chilipepper Rockfish', 0, 0, 0),
('china_rockfish', 'China Rockfish', 0, 0, 0),
('chip', 'Chip', 0, 0, 0),
('chip_10', '$10 Chip', 0, 0, 0),
('chip_100', '$100 Chip', 0, 0, 0),
('chip_1000', '$1000 Chip', 0, 0, 0),
('chip_10000', '$10000 Chip', 0, 0, 0),
('chip_50', '$50 Chip', 0, 0, 0),
('chip_500', '$500 Chip', 0, 0, 0),
('chip_5000', '$5000 Chip', 0, 0, 0),
('chocolate_cake', 'Chocolate Cake', 0, 0, 1),
('chocolate_cake_slice', 'Chocolate Cake Slice', 0, 0, 1),
('chocolate_ice_cream', 'Chocolate Ice Cream', 0, 0, 1),
('chocolate_milkshake', 'Chocolate Milkshake', 0, 0, 1),
('chorus_fruit', 'Chorus Fruit', 0, 0, 1),
('cider', 'Cider', 0, 0, 1),
('cigar', 'Cigar', 0, 0, 0),
('cigar_arturo', 'Arturo Fuente Gran Reserva', 0, 0, 0),
('cigar_cohiba', 'Cohiba', 0, 0, 0),
('cigar_homemade', 'Cigar (Hand-rolled)', 0, 0, 0),
('cigar_olivia', 'Oliva Serie G', 0, 0, 0),
('cigar_romeo', 'Romeo y Julieta 1875', 0, 0, 0),
('cigarette', 'Cigarette', 0, 0, 0),
('cigarette_carton', 'Cigarette Carton', 0, 0, 0),
('cigarette_pack', 'Cigarette Pack', 0, 0, 0),
('citizen_card', 'Citizen Card', 0, 0, 0),
('claymore', 'Claymore', 0, 0, 0),
('cleaning_kit', 'Cleaning Kit', 0, 0, 0),
('closed_paper_bag', 'Closed Paper Bag', 0, 0, 0),
('cloth_tent', 'Cloth Tent', 0, 0, 0),
('clothing_bag', 'Clothing Bag', 0, 0, 0),
('clover', '4 Leaf Clover', 0, 0, 0),
('clover_mk2', '4 Leaf Clover MK2', 0, 0, 0),
('cocaine_bag', 'Cocaine Bag', 0, 1, 0),
('cocaine_brick', 'Cocaine Brick', 0, 0, 0),
('cocoa_beans', 'Cocoa Beans', 0, 0, 0),
('cocoa_powder', 'Cocoa Powder', 0, 0, 0),
('coconut', 'Coconut', 0, 0, 0),
('coffee_beans', 'Coffee Beans', 0, 0, 1),
('coin_bag', 'Coin Bag', 0, 0, 0),
('coke', 'Coke', 0, 0, 1),
('color_measurer', 'Color Measurer', 0, 0, 0),
('compass', 'Compass', 0, 0, 0),
('cone', 'Cone', 0, 0, 0),
('cooked_meat', 'Cooked Meat', 0, 0, 1),
('cooler_box', 'Cooler Box', 0, 0, 0),
('copper_nugget', 'Copper Nugget', 0, 0, 0),
('copper_rockfish_variant_1', 'Copper Rockfish (Variant 1)', 0, 0, 0),
('copper_rockfish_variant_2', 'Copper Rockfish (Variant 2)', 0, 0, 0),
('copper_wire', 'Copper Wire', 0, 0, 0),
('cowcod', 'Cowcod', 0, 0, 0),
('cpu', 'CPU', 0, 0, 0),
('crack', 'Crack', 0, 1, 0),
('cream_cookie', 'Cream Cookie', 0, 0, 1),
('cucumber', 'Cucumber', 0, 0, 0),
('cupcake', 'Cupcake', 0, 0, 1),
('dab_pen', 'Penjamin', 0, 0, 0),
('dark_chocolate', 'Dark Chocolate', 0, 0, 1),
('darkblotched_rockfish', 'Darkblotched Rockfish', 0, 0, 0),
('deacon_rockfish', 'Deacon Rockfish', 0, 0, 0),
('deck_arcade', 'Arcade Attack Deck', 0, 0, 0),
('deck_blossom', 'Cherry Blossom Deck', 0, 0, 0),
('deck_cats', 'Feline Frenzy Deck', 0, 0, 0),
('deck_ems', 'Red Line Deck', 0, 0, 0),
('deck_flowers', 'Tropical Vibes Deck', 0, 0, 0),
('deck_peace', 'Psychedelic Serenity Deck', 0, 0, 0),
('deck_police', 'Blue Line Deck', 0, 0, 0),
('deck_simpsons', 'Bart\'s Mayhem Deck', 0, 0, 0),
('deck_usa', 'Liberty Deck', 0, 0, 0),
('deck_weed', 'High Speed Deck', 0, 0, 0),
('decryption_key_blue', 'Blue Decryption Key', 0, 0, 0),
('decryption_key_green', 'Green Decryption Key', 0, 0, 0),
('decryption_key_red', 'Red Decryption Key', 0, 0, 0),
('device_printout', 'Device Printout', 0, 0, 0),
('device_scanner', 'Device Scanner', 0, 0, 0),
('diamond_ring', 'Diamond Ring', 0, 0, 0),
('diamonds', 'Diamonds', 0, 0, 0),
('director_chair', 'Director Chair', 0, 0, 0),
('disposable_grill', 'Disposable Grill', 0, 0, 0),
('doc_badge', 'DOC Badge', 0, 0, 0),
('doctor_badge', 'Doctor ID', 0, 0, 0),
('document_paper', 'Document Paper (21x28)', 0, 0, 0),
('dog_0', 'Westie Terrier', 0, 0, 0),
('dog_1', 'Pug', 0, 0, 0),
('dog_2', 'Poodle', 0, 0, 0),
('dog_food', 'Dog Food', 0, 0, 1),
('dog_treats', 'Dog Treats', 0, 0, 1),
('doj_badge', 'DOJ Badge', 0, 0, 0),
('donut', 'Donut', 0, 0, 1),
('drill', 'Drill', 0, 0, 0),
('drill_large', 'Large Drill', 0, 0, 0),
('drill_small', 'Small Drill', 0, 0, 0),
('driver_license', 'Driver\'s License', 0, 0, 0),
('drum', 'Drum Mag', 0, 0, 0),
('dummy', 'Dummy', 0, 0, 0),
('dusky_rockfish_dark_version', 'Dusky Rockfish (Dark Version)', 0, 0, 0),
('dusky_rockfish_light_version', 'Dusky Rockfish (Light Version)', 0, 0, 0),
('ear_defenders', 'Ear Defenders', 0, 0, 0),
('earthworms', 'Earthworms', 0, 0, 0),
('eggs', 'Eggs', 0, 0, 0),
('ejector_seat', 'Ejector Seat', 0, 0, 0),
('electric_fuse', 'Electric Fuse', 0, 0, 0),
('emerald', 'Emerald', 0, 0, 0),
('emerald_ring', 'Emerald Ring', 0, 0, 0),
('empty_box', 'Empty Box', 0, 0, 0),
('empty_nitro_tank', 'Empty Nitro Tank', 0, 0, 0),
('empty_tank', 'Empty Tank', 0, 0, 0),
('ems_badge', 'EMS ID', 0, 0, 0),
('espresso', 'Espresso', 0, 0, 1),
('ev_battery', 'EV Battery', 0, 0, 0),
('evidence_bag', 'Evidence Bag', 0, 0, 0),
('evidence_bag_empty', 'Empty Evidence Bag', 0, 0, 0),
('evidence_box', 'Evidence Box', 0, 0, 0),
('evidence_marker_1', 'Marker 1', 0, 0, 0),
('evidence_marker_2', 'Marker 2', 0, 0, 0),
('evidence_marker_3', 'Marker 3', 0, 0, 0),
('evidence_marker_4', 'Marker 4', 0, 0, 0),
('evidence_marker_5', 'Marker 5', 0, 0, 0),
('extended_clip', 'Extended Clip', 0, 0, 0),
('extended_pistol_clip', 'Extended Clip (Pistol)', 0, 0, 0),
('extended_shotgun_clip', 'Extended Clip (Shotgun)', 0, 0, 0),
('extended_smg_clip', 'Extended Clip (SMG)', 0, 0, 0),
('fake_plate', 'Fake Plate', 0, 0, 0),
('fanta_light', 'Fanta Light', 0, 0, 1),
('fentanyl', 'Fentanyl', 0, 1, 0),
('fertilizer', 'Fertilizer', 0, 0, 0),
('fib_badge', 'FIB Badge', 0, 0, 0),
('fibreglass_resin', 'Fibreglass Resin', 0, 0, 0),
('fingerprint_evidence', 'Fingerprint Evidence', 0, 0, 0),
('firework_battery', 'Firework Battery', 0, 0, 0),
('firework_rocket', 'Firework Rocket', 0, 0, 0),
('first_aid_kit', 'First Aid Kit', 0, 0, 0),
('fish_filets', 'Fish Filets', 0, 0, 1),
('fish_sauce', 'Fish Sauce', 0, 0, 1),
('fishing_chair', 'Fishing Chair', 0, 0, 0),
('fishing_license', 'Fishing License', 0, 0, 0),
('fishing_rod', 'Fishing Rod', 0, 0, 0),
('flag', 'Flag', 0, 0, 0),
('flag_rockfish', 'Flag Rockfish', 0, 0, 0),
('flashlight', 'Flashlight', 0, 0, 0),
('flight_radar', 'Flight Radar', 0, 0, 0),
('floodlight', 'Floodlight', 0, 0, 0),
('flour', 'Flour', 0, 0, 1),
('folder', 'Folder', 0, 0, 0),
('fortune_cookie', 'Fortune Cookie', 0, 0, 0),
('fortune_paper', 'Fortune Paper', 0, 0, 0),
('fried_egg', 'Fried Egg', 0, 0, 0),
('ftp_badge', 'FTP Badge', 0, 0, 0),
('gadget_parachute', 'Parachute', 1, 0, 0),
('gas_mask', 'Gas Mask', 0, 0, 0),
('gasoline_bottle', 'Gasoline Bottle', 0, 0, 0),
('gauze', 'Gauze', 0, 0, 0),
('gemstone_scanner', 'Gemstone Scanner', 0, 0, 0),
('generic_prescription', 'Generic Prescription', 0, 0, 0),
('gift_box', 'Gift Box', 0, 0, 0),
('gift_box_bomb', 'Gift Box', 0, 0, 0),
('glass', 'Rough Glass', 0, 0, 0),
('glass_breaker', 'Emergency Window Breaker', 0, 0, 0),
('glass_pipe', 'Glass Pipe', 0, 0, 0),
('gold_bar', 'Gold Bar', 0, 0, 0),
('gold_nugget', 'Gold Nugget', 0, 0, 0),
('gold_ore', 'Gold Ore', 0, 0, 0),
('gold_watches', 'Gold Watches', 0, 0, 0),
('golf_ball', 'Golf Ball', 0, 0, 0),
('golf_ball_orange', 'Orange Golf Ball', 0, 0, 0),
('golf_ball_pink', 'Pink Golf Ball', 0, 0, 0),
('golf_ball_yellow', 'Yellow Golf Ball', 0, 0, 0),
('gopher_rockfish', 'Gopher Rockfish', 0, 0, 0),
('gps', 'GPS', 0, 0, 0),
('gps_collar', 'GPS Collar', 0, 0, 0),
('grass_rockfish_dark_version', 'Grass Rockfish (Dark Version)', 0, 0, 0),
('grass_rockfish_light_version', 'Grass Rockfish (Light Version)', 0, 0, 0),
('green_apple', 'Green Apple', 0, 0, 1),
('green_fishing_chair', 'Green Fishing Chair', 0, 0, 0),
('green_hiking_backpack', 'Green Hiking Backpack', 0, 0, 0),
('green_rolls', 'Green Rolls', 0, 0, 0),
('green_tea', 'Green Tea', 0, 0, 1),
('green_tea_bag', 'Green Tea', 0, 0, 1),
('green_wonderland_delivery', 'Green Wonderland Bag', 0, 0, 0),
('greenblotched_rockfish', 'Greenblotched Rockfish', 0, 0, 0),
('greenspotted_rockfish', 'Greenspotted Rockfish', 0, 0, 0),
('greenstriped_rockfish', 'Greenstriped Rockfish', 0, 0, 0),
('grenade_pin', 'Grenade Pin', 0, 0, 0),
('grenade_shell', 'Grenade Shell', 0, 0, 0),
('grill', 'Grill', 0, 0, 0),
('grilled_bacon', 'Grilled Bacon', 0, 0, 0),
('grilled_sausages', 'Grilled Sausages', 0, 0, 0),
('grimace_shake', 'Grimace Shake', 0, 1, 0),
('grip', 'Grip', 0, 0, 0),
('grubs', 'Grubs', 0, 0, 0),
('guinness_beer', 'Guinness', 0, 0, 1),
('gumball', 'Gumball', 0, 0, 1),
('gunpowder', 'Gunpowder', 0, 0, 0),
('halfbanded_rockfish', 'Halfbanded Rockfish', 0, 0, 0),
('ham', 'Ham', 0, 0, 1),
('hamburger', 'Hamburger', 0, 0, 1),
('handcuffs', 'Handcuffs', 0, 0, 0),
('hardened_steel_plate', 'Hardened Steel Plate', 0, 0, 0),
('hen_0', 'Chicken', 0, 0, 0),
('high_tensile_spring', 'High Tensile Spring', 0, 0, 0),
('hiking_backpack', 'Hiking Backpack', 0, 0, 0),
('honeycomb_rockfish', 'Honeycomb Rockfish', 0, 0, 0),
('hostage_1', 'Hostage 1', 0, 0, 0),
('hostage_2', 'Hostage 2', 0, 0, 0),
('hot_chocolate', 'Hot Chocolate', 0, 0, 1),
('hot_dog', 'Hot Dog', 0, 0, 1),
('hotwheels_mcqueen', 'Lightning McQueen', 0, 0, 0),
('hotwheels_towmater', 'Tow Mater', 0, 0, 0),
('hunting_license', 'Hunting License', 0, 0, 0),
('hydrogen_peroxide', 'Hydrogen Peroxide', 0, 0, 0),
('iaa_badge', 'IAA Badge', 0, 0, 0),
('iced_latte', 'Iced Latte', 0, 0, 1),
('ifak', 'IFAK', 0, 0, 0),
('irish_coffee', 'Irish Coffee', 0, 0, 1),
('iron_ore', 'Iron Ore', 0, 0, 0),
('iron_oxide', 'Iron Oxide Powder', 0, 0, 0),
('jack_o_lantern', 'Jack O\' Lantern', 0, 0, 0),
('jail_card', 'Jail Card', 0, 0, 0),
('jalapeno', 'Jalapeno', 0, 0, 1),
('jameson_whiskey', 'Jameson', 0, 0, 1),
('joint', 'Joint', 0, 1, 0),
('jolly_rancher_apple', 'Apple Jolly Rancher', 0, 0, 1),
('jolly_rancher_cherry', 'Cherry Jolly Rancher', 0, 0, 1),
('jolly_rancher_grape', 'Grape Jolly Rancher', 0, 0, 1),
('jolly_rancher_raspberry', 'Raspberry Jolly Rancher', 0, 0, 1),
('jolly_rancher_watermelon', 'Watermelon Jolly Rancher', 0, 0, 1),
('jolly_ranchers', 'Jolly Ranchers', 0, 0, 0),
('kelp_greenling_female', 'Kelp Greenling (female)', 0, 0, 0),
('kelp_greenling_male', 'Kelp Greenling (male)', 0, 0, 0),
('kelp_rockfish', 'Kelp Rockfish', 0, 0, 0),
('kettle_chips', 'Kettle Chips (Honey-BBQ)', 0, 0, 1),
('keycard_blue', 'Blue Keycard', 0, 0, 0),
('keycard_green', 'Green Keycard', 0, 0, 0),
('keycard_red', 'Red Keycard', 0, 0, 0),
('keys', 'Keys', 0, 0, 0),
('kimchi', 'Kimchi', 0, 0, 1),
('kinder_surprise', 'Kinder Susprise Egg', 0, 0, 1),
('kissaki_delivery', 'Kissaki Meal', 0, 0, 0),
('kiwi', 'Kiwi', 0, 0, 1),
('knob', 'Knob', 0, 0, 0),
('label_printer', 'Label Printer', 0, 0, 0),
('ladder', 'Ladder', 0, 0, 0),
('large_target', 'Large Target', 0, 0, 0),
('lavalamp', 'Lavalamp', 0, 0, 0),
('lean', 'Lean', 0, 1, 0),
('leash', 'Leash', 0, 0, 0),
('leather', 'Leather', 0, 0, 0),
('leeches', 'Leeches', 0, 0, 0),
('left_diversion_sign', 'Left Diversion Sign', 0, 0, 0),
('lemon', 'Lemon', 0, 0, 1),
('lemon_cake', 'Lemon Cake', 0, 0, 1),
('lemon_cake_slice', 'Lemon Cake Slice', 0, 0, 1),
('lens', 'Lens', 0, 0, 0),
('lettuce', 'Lettuce', 0, 0, 0),
('lighter', 'Lighter', 0, 0, 0),
('lime', 'Lime', 0, 0, 0),
('lingcod', 'Lingcod', 0, 0, 0),
('liquid_smoke', 'Liquid Smoke', 0, 0, 0),
('lithium_batteries', 'Lithium Batteries', 0, 0, 0),
('lollipop_apple', 'Apple Lollipop', 0, 0, 1),
('lollipop_coke', 'Coke Lollipop', 0, 0, 1),
('lollipop_grape', 'Grape Lollipop', 0, 0, 1),
('lollipop_pack', 'Lollipop Pack', 0, 0, 0),
('lollipop_raspberry', 'Raspberry Lollipop', 0, 0, 1),
('lollipop_strawberry', 'Strawberry Lollipop', 0, 0, 1),
('lollipop_watermelon', 'Watermelon Lollipop', 0, 0, 1),
('lucky_penny', 'Lucky Penny', 0, 0, 0),
('lunch_box', 'Lunch Box', 0, 0, 0),
('magazine', 'Magazine', 0, 0, 0),
('magic_ball', 'Magic 8-Ball', 0, 0, 0),
('magnifying_glass', 'Magnifying Glass', 0, 0, 0),
('management_badge', 'Management Badge', 0, 0, 0),
('mango', 'Mango', 0, 0, 1),
('map', 'Map', 0, 0, 0),
('meth_bag', 'Meth Bag', 0, 1, 0),
('meth_pipe', 'Meth Pipe', 0, 0, 0),
('meth_table', 'Meth Table', 0, 0, 0),
('microcontroller', 'Microcontroller', 0, 0, 0),
('microphone_bug', 'Microphone Bug', 0, 0, 0),
('microphone_stand', 'Microphone Stand', 0, 0, 0),
('milk', 'Milk', 0, 0, 1),
('mine', 'Mine', 0, 0, 0),
('mining_license', 'Mining License', 0, 0, 0),
('miso_soup', 'Miso Soup', 0, 0, 1),
('mochi_chocolate', 'Chocolate Mochi', 0, 0, 1),
('mochi_green_tea', 'Green Tea Mochi', 0, 0, 1),
('mochi_mango', 'Mango Mochi', 0, 0, 1),
('mochi_strawberry', 'Strawberry Mochi', 0, 0, 1),
('moonshine', 'Moonshine', 0, 1, 0),
('morganite', 'Morganite', 0, 0, 0),
('morganite_ring', 'Morganite Ring', 0, 0, 0),
('motor_oil', 'Motor Oil', 0, 0, 0),
('mozarella', 'Mozarella', 0, 0, 1),
('multi_tool', 'Multi Tool', 0, 0, 0),
('muzzle_brake', 'Muzzle Brake', 0, 0, 0),
('nachos', 'Nachos', 0, 0, 1),
('narcan', 'Narcan', 0, 0, 0),
('necklaces', 'Necklaces', 0, 0, 0),
('nerds_chunks', 'Nerds Chunks', 0, 0, 1),
('nigiri', 'Nigiri', 0, 0, 1),
('nitro_tank', 'Nitro Tank', 0, 0, 0),
('nori', 'Nori', 0, 0, 0),
('note', 'Note', 0, 0, 0),
('nv_goggles', 'Night Vision Goggles', 0, 0, 0),
('old_rug', 'Old Rug', 0, 0, 0),
('olive_oil', 'Olive Oil', 0, 0, 1),
('olive_rockfish', 'Olive Rockfish', 0, 0, 0),
('olives', 'Olives', 0, 0, 1),
('onyx', 'Onyx', 0, 0, 0),
('onyx_ring', 'Onyx Ring', 0, 0, 0),
('opal', 'Opal', 0, 0, 0),
('opal_ring', 'Opal Ring', 0, 0, 0),
('orange', 'Orange', 0, 0, 1),
('orange_juice', 'Orange Juice', 0, 0, 1),
('oreos', 'Birthday-Cake Oreos', 0, 0, 1),
('oxy', 'Oxy', 0, 1, 0),
('oxy_prescription', 'Oxy Prescription', 0, 0, 0),
('oxygen_tank', 'Oxygen Tank', 0, 0, 0),
('pacific_ocean_perch', 'Pacific Ocean Perch', 0, 0, 0),
('pacific_sand_sole', 'Pacific Sand Sole', 0, 0, 0),
('pacific_sanddab', 'Pacific Sanddab', 0, 0, 0),
('pager', 'Pager', 0, 0, 0),
('pain_killers', 'Ibuprofen', 0, 1, 0),
('paint', 'Paint', 0, 0, 0),
('paint_brush', 'Paint Brush', 0, 0, 0),
('pancake_batter', 'Pancake Batter', 0, 0, 1),
('pancake_mix', 'Pancake Mix', 0, 0, 1),
('pancakes', 'Pancakes', 0, 0, 1),
('paper', 'Photo Paper (1x1)', 0, 0, 0),
('paper_bag', 'Paper Bag', 0, 0, 0),
('paper_straw', 'Paper Straw', 0, 0, 0),
('paper_wide', 'Photo Paper (14x8.5)', 0, 0, 0),
('parasol', 'Parasol', 0, 0, 0),
('parasol_table', 'Parasol Table', 0, 0, 0),
('patty', 'Burger Patty', 0, 0, 0),
('pcb_board', 'PCB Board', 0, 0, 0),
('peach', 'Peach', 0, 0, 1),
('peanuts', 'Salted Peanuts', 0, 0, 1),
('pearl', 'Pearl', 0, 0, 0),
('pearl_ring', 'Pearl Ring', 0, 0, 0),
('pedestrian_barrier', 'Pedestrian Barrier', 0, 0, 0),
('pepper_spray', 'Pepper Spray', 0, 0, 0),
('pepperoni', 'Pepperoni', 0, 0, 1),
('pepsi', 'Pepsi', 0, 0, 1),
('pet_banana_cat', 'Banana Cat', 0, 0, 0),
('pet_cat', 'Shoulder Snuggler', 0, 0, 0),
('pet_cat_grey', 'Lazy Gizmo', 0, 0, 0),
('pet_chicken', 'Feathery Friend', 0, 0, 0),
('pet_duck', 'Quacktastic Sidekick', 0, 0, 0),
('pet_flamingo', 'Fancy Floof', 0, 0, 0),
('pet_mouse', 'Pudgy Pal', 0, 0, 0),
('pet_owl', 'Hooty', 0, 0, 0),
('pet_pig', 'Porkchop', 0, 0, 0),
('pet_pingu', 'Pingu', 0, 0, 0),
('pet_porg', 'Porg Pal', 0, 0, 0),
('pet_raccoon', 'Rascal the Raccoon', 0, 0, 0),
('pet_shiba', 'Paw Patrol', 0, 0, 0),
('pet_snowman', '\"Frosty\" The Snowman', 0, 0, 0),
('phone', 'Phone', 0, 0, 0),
('photo_camera', 'Photo Camera', 0, 0, 0),
('pickaxe', 'Pickaxe', 0, 0, 0),
('pickle', 'Pickle', 0, 0, 1),
('pickle_juice', 'Pickle Juice', 0, 0, 1),
('pickles', 'Pickles', 0, 0, 1),
('picture', 'Picture', 0, 0, 0),
('picture_wide', 'Picture', 0, 0, 0),
('pigeon_milk', 'Pigeon Milk', 0, 0, 1),
('pilk', 'Pilk', 0, 0, 1),
('pilot_license', 'Pilot License', 0, 0, 0),
('pineapple', 'Pineapple', 0, 0, 1),
('pineapple_cake', 'Pineapple Cake', 0, 0, 1),
('pineapple_slices', 'Pineapple Slices', 0, 0, 1),
('pink_dildo', 'Pink Dildo', 0, 0, 0),
('pink_lemonade', 'Pink Lemonade', 0, 0, 1),
('pistol_ammo', 'Pistol Ammo', 0, 0, 0),
('pistol_sight', 'Pistol Sight', 0, 0, 0),
('pizza_cheese', 'Pizza Cheese', 0, 0, 1),
('pizza_diavola', 'Diavola Pizza', 0, 0, 1),
('pizza_diavola_raw', 'Raw Diavola Pizza', 0, 0, 1),
('pizza_dough', 'Pizza Dough', 0, 0, 1),
('pizza_ham', 'Ham Pizza', 0, 0, 1),
('pizza_ham_raw', 'Raw Ham Pizza', 0, 0, 1),
('pizza_hawaiian', 'Hawaiian Pizza', 0, 0, 1),
('pizza_hawaiian_raw', 'Raw Hawaiian Pizza', 0, 0, 1),
('pizza_margherita', 'Margherita Pizza', 0, 0, 1),
('pizza_margherita_raw', 'Raw Margherita Pizza', 0, 0, 1),
('pizza_pepperoni', 'Pepperoni Pizza', 0, 0, 1),
('pizza_pepperoni_raw', 'Raw Pepperoni Pizza', 0, 0, 1),
('pizza_salami', 'Salami Pizza', 0, 0, 1),
('pizza_salami_raw', 'Raw Salami Pizza', 0, 0, 1),
('pizza_saver', 'Pizza Saver', 0, 0, 0),
('pizza_slice', 'Margherita Pizza Slice', 0, 0, 1),
('pizza_slice_diavola', 'Diavola Pizza Slice', 0, 0, 1),
('pizza_slice_ham', 'Ham Pizza Slice', 0, 0, 1),
('pizza_slice_hawaiian', 'Hawaiian Pizza Slice', 0, 0, 1),
('pizza_slice_pepperoni', 'Pepperoni Pizza Slice', 0, 0, 1),
('pizza_slice_salami', 'Salami Pizza Slice', 0, 0, 1),
('pizza_slice_vegetarian', 'Vegetarian Pizza Slice', 0, 0, 1),
('pizza_this_delivery', 'Pizza This Box', 0, 0, 0),
('pizza_vegetarian', 'Vegetarian Pizza', 0, 0, 1),
('pizza_vegetarian_raw', 'Raw Vegetarian Pizza', 0, 0, 1),
('plastic_chair', 'Plastic Chair', 0, 0, 0),
('plush_blue', 'Sparky McBowtie', 0, 0, 0),
('plush_green', 'Mossy McHairface', 0, 0, 0),
('plush_orange', 'Tang the Explorer', 0, 0, 0),
('plush_pink', 'Sir Fancy Pants', 0, 0, 0),
('plush_red', 'Shades the Superstar', 0, 0, 0),
('plush_wasabi', 'Wasabi Whiz', 0, 0, 0),
('plush_white', 'Captain Whiskerface', 0, 0, 0),
('plush_yellow', 'Sunshine Dread', 0, 0, 0),
('pole', 'Yellow Pole', 0, 0, 0),
('police_barrier', 'Police Barrier', 0, 0, 0),
('polymer_resin', 'Polymer Resin', 0, 0, 0),
('pomegranate', 'Pomegranate', 0, 0, 1),
('popcorn', 'Popcorn', 0, 0, 1),
('potassium_nitrate', 'Potassium Nitrate', 0, 0, 0),
('potato', 'Potato', 0, 0, 0),
('power_saw', 'Sawzall', 0, 0, 0),
('press_pass', 'Press Pass', 0, 0, 0),
('printed_card', 'Printed Card', 0, 0, 0),
('printed_document', 'Printed Document', 0, 0, 0),
('printer', 'Printer', 0, 0, 0),
('processed_metal', 'Processed Metal', 0, 0, 0),
('projectile', 'Projectile', 0, 0, 0),
('pumpkin', 'Pumpkin', 0, 0, 0),
('purified_aluminium', 'Purified Aluminium', 0, 0, 0),
('pvc_pipe', 'PVC Pipe', 0, 0, 0),
('quesadilla', 'Queasadilla', 0, 0, 1),
('quillback_rockfish_variant_1', 'Quillback Rockfish (Variant 1)', 0, 0, 0),
('quillback_rockfish_variant_2', 'Quillback Rockfish (Variant 2)', 0, 0, 0),
('rabbit_0', 'Dark Brown Rabbit', 0, 0, 0),
('rabbit_1', 'Light Brown Rabbit', 0, 0, 0),
('rabbit_2', 'Tan Rabbit', 0, 0, 0),
('rabbit_3', 'Gray Rabbit', 0, 0, 0),
('radio', 'Radio', 0, 0, 0),
('radio_chop_shop', 'Chop Shop Radio', 0, 0, 0),
('radio_decryptor', 'Radio Decrypter', 0, 0, 0),
('radio_jammer', 'Radio Jammer', 0, 0, 0),
('ramen', 'Ramen', 0, 0, 1),
('raspberry', 'Raspberry', 0, 0, 0),
('rat_0', 'Rat', 0, 0, 0),
('raw_bacon', 'Raw Bacon', 0, 0, 0),
('raw_brined_meat', 'Raw Brined Meat', 0, 0, 1),
('raw_diamond', 'Raw Diamond', 0, 0, 0),
('raw_emerald', 'Raw Emerald', 0, 0, 0),
('raw_fries', 'Raw Fries', 0, 0, 0),
('raw_meat', 'Raw Meat', 0, 0, 1),
('raw_morganite', 'Raw Morganite', 0, 0, 0),
('raw_onyx', 'Raw Onyx', 0, 0, 0),
('raw_opal', 'Raw Opal', 0, 0, 0),
('raw_patty', 'Raw Patty', 0, 0, 0),
('raw_ruby', 'Raw Ruby', 0, 0, 0),
('raw_sapphire', 'Raw Sapphire', 0, 0, 0),
('red_parachute', 'Red Parachute', 1, 0, 0),
('red_pillow', 'Red Pillow', 0, 0, 0),
('redbanded_rockfish', 'Redbanded Rockfish', 0, 0, 0),
('reeses_pieces', 'Reese\'s Pieces', 0, 0, 1),
('refillable_bottle', 'Refillable Bottle', 0, 0, 0),
('refined_steel', 'Refined Steel', 0, 0, 0),
('reinforced_steel_tube', 'Reinforced Steel Tube', 0, 0, 0),
('remote_camera', 'Remote Camera', 0, 0, 0),
('remote_monitor', 'Remote Monitor', 0, 0, 0),
('rice', 'Cooked Rice', 0, 0, 0),
('rice_krispies', 'Rice Krispies', 0, 0, 1),
('rifle_ammo', 'Rifle Ammo', 0, 0, 0),
('rifle_lower_receiver', 'Rifle Lower Receiver', 0, 0, 0),
('rifle_lower_receiver_mk2', 'Rifle Lower Receiver MK2', 0, 0, 0),
('rifle_upper_receiver', 'Rifle Upper Receiver', 0, 0, 0),
('rifle_upper_receiver_mk2', 'Rifle Upper Receiver MK2', 0, 0, 0),
('right_diversion_sign', 'Right Diversion Sign', 0, 0, 0),
('ring', 'Ring', 0, 0, 0),
('rock_sole', 'Rock Sole', 0, 0, 0),
('rolling_paper', 'Rolling Paper', 0, 0, 0),
('rose', 'Rose', 0, 0, 0),
('rosy_rockfish', 'Rosy Rockfish', 0, 0, 0),
('rougheye_rockfish', 'Rougheye Rockfish', 0, 0, 0),
('rubber', 'Uncured Rubber', 0, 0, 0),
('ruby', 'Ruby', 0, 0, 0),
('ruby_dust', 'Ruby Dust', 0, 0, 0),
('ruby_ring', 'Ruby Ring', 0, 0, 0),
('rum', 'Rum', 0, 0, 1),
('rusty_cannon_ball', 'Rusty Cannon Ball', 0, 0, 0),
('rusty_diving_helmet', 'Rusty Diving Helmet', 0, 0, 0),
('rusty_gear', 'Rusty Gear', 0, 0, 0),
('rusty_tank_shell', 'Rusty Tank Shell', 0, 0, 0),
('sahp_badge', 'SAHP Badge', 0, 0, 0),
('salami', 'Salami', 0, 0, 1),
('salt', 'Salt', 0, 0, 0),
('sandwich', 'Ham Sandwich', 0, 0, 1),
('sapphire', 'Sapphire', 0, 0, 0),
('sapphire_dust', 'Sapphire Dust', 0, 0, 0),
('sapphire_ring', 'Sapphire Ring', 0, 0, 0),
('sasp_badge', 'SASP Badge', 0, 0, 0),
('savings_bond_1000', '$1,000 Savings Bond', 0, 0, 0),
('savings_bond_200', '$200 Savings Bond', 0, 0, 0),
('savings_bond_2000', '$2,000 Savings Bond', 0, 0, 0),
('savings_bond_500', '$500 Savings Bond', 0, 0, 0),
('scope', 'Scope', 0, 0, 0),
('scrap_metal', 'Scrap Metal', 0, 0, 0),
('scratch_remover', 'Scratch Remover', 0, 0, 0),
('scratch_ticket', 'Scratch-Off (Cash Extravaganza)', 0, 0, 0),
('scratch_ticket_beaver', 'Scratch-Off (Los Santos)', 0, 0, 0),
('scratch_ticket_carnival', 'Scratch-Off (Carnival)', 0, 0, 0),
('scratch_ticket_ching', 'Scratch-Off (Cha Ching)', 0, 0, 0),
('scratch_ticket_minecraft', 'Scratch-Off (Minecraft)', 0, 0, 0),
('scratch_ticket_pearl', 'Scratch-Off (Black Pearl)', 0, 0, 0),
('scratch_ticket_vu', 'Scratch-Off (Vanilla Unicorn)', 0, 0, 0),
('screen', 'Screen', 0, 0, 0),
('screws', 'Screws', 0, 0, 0),
('sd_card', 'SD Card', 0, 0, 0),
('seashell', 'Seashell', 0, 0, 0),
('self_driving_chip', 'Self-Driving Chip', 0, 0, 0),
('sheet_metal', 'Sheet Metal', 0, 0, 0),
('shortraker_rockfish', 'Shortraker Rockfish', 0, 0, 0),
('shotgun_ammo', 'Shotgun Ammo', 0, 0, 0),
('shotgun_lower_receiver', 'Shotgun Lower Receiver', 0, 0, 0),
('shotgun_lower_receiver_mk2', 'Shotgun Lower Receiver MK2', 0, 0, 0),
('shotgun_upper_receiver', 'Shotgun Upper Receiver', 0, 0, 0),
('shovel', 'Shovel', 0, 0, 0),
('shrooms', 'Shrooms', 0, 1, 0),
('sight', 'Holographic Sight', 0, 0, 0),
('silver_watches', 'Silver Watches', 0, 0, 0),
('silvergray_rockfish', 'Silvergray Rockfish', 0, 0, 0),
('skate_helmet', 'Skate Helmet', 0, 0, 0),
('skateboard', 'Skateboard', 0, 0, 0),
('skin_brushstroke', 'Brushstroke Skin', 0, 0, 0),
('skin_geometric', 'Geometric Skin', 0, 0, 0),
('skin_leopard', 'Leopard Skin', 0, 0, 0),
('skin_patriotic', 'Patriotic Skin', 0, 0, 0),
('skin_skull', 'Skull Skin', 0, 0, 0),
('skin_zebra', 'Zebra Skin', 0, 0, 0),
('sleeping_bag', 'Sleeping Bag', 0, 0, 0),
('small_barrier', 'Small Barrier', 0, 0, 0),
('small_frog', 'Small Frog', 0, 0, 0),
('small_frog_mk2', 'Small Frog MK2', 0, 0, 0),
('smart_watch', 'Smart Watch', 0, 0, 0),
('smg_lower_receiver', 'SMG Lower Receiver', 0, 0, 0),
('smg_lower_receiver_mk2', 'SMG Lower Receiver MK2', 0, 0, 0),
('smg_upper_receiver', 'SMG Upper Receiver', 0, 0, 0),
('smg_upper_receiver_mk2', 'SMG Upper Receiver MK2', 0, 0, 0),
('smoothie', 'Smoothie', 0, 0, 1),
('smores', 'S\'mores', 0, 0, 1),
('sniper_ammo', 'Sniper Ammo', 0, 0, 0),
('snus', 'Snus', 0, 0, 0),
('snus_pack', 'Snus Can', 0, 0, 0),
('soy_sauce', 'Soy Sauce', 0, 0, 0),
('speckled_rockfish', 'Speckled Rockfish', 0, 0, 0),
('speed_bump', 'Speed Bump', 0, 0, 0),
('speed_sign', 'Speed Limit Sign', 0, 0, 0),
('spicy_ramen', 'Spicy Ramen', 0, 0, 1),
('spike_strips', 'Spike Strips', 0, 0, 0),
('spike_strips_large', 'Large Spike Strips', 0, 0, 0),
('spotlight', 'Spotlight', 0, 0, 0),
('spring', 'Spring', 0, 0, 0),
('spring_onions', 'Spring Onions', 0, 0, 1),
('spring_onions_cut', 'Cut Spring Onions', 0, 0, 1),
('sprite', 'Sprite', 0, 0, 1),
('squarespot_rockfish', 'Squarespot Rockfish', 0, 0, 0),
('starry_flounder', 'Starry Flounder', 0, 0, 0),
('starry_rockfish', 'Starry Rockfish', 0, 0, 0),
('state_badge', 'State ID', 0, 0, 0),
('state_security_badge', 'State Security ID', 0, 0, 0),
('steel', 'Raw Steel', 0, 0, 0),
('steel_file', 'Steel File', 0, 0, 0),
('steel_filings', 'Steel Filings', 0, 0, 0),
('steel_tube', 'Steel Tube', 0, 0, 0),
('stop_sign', 'Stop Sign', 0, 0, 0),
('stop_sticks', 'Stop Sticks', 0, 0, 0),
('strawberry', 'Strawberry', 0, 0, 1),
('stungun_ammo', 'Taser Cartridge', 0, 0, 0),
('sub_ammo', 'Sub Ammo', 0, 0, 0),
('sugar', 'Sugar', 0, 0, 0),
('sulfur', 'Sulfur', 0, 0, 0),
('suppressor', 'Suppressor', 0, 0, 0),
('sushi', 'Sushi', 0, 0, 1),
('swat_badge', 'SWAT Badge', 0, 0, 0),
('table', 'Table', 0, 0, 0),
('tablet', 'Tablet', 0, 0, 0),
('taco', 'Taco', 0, 0, 1),
('target', 'Target', 0, 0, 0),
('tayto_chips', 'Tayto Chips', 0, 0, 1),
('teddy_bear', 'Teddy Bear', 0, 0, 0),
('tempered_glass', 'Tempered Glass', 0, 0, 0),
('tent', 'Tent', 0, 0, 0),
('tequila', 'Tequila', 0, 0, 1),
('thermal_goggles', 'Thermal Goggles', 0, 0, 0),
('thermite', 'Thermite', 0, 0, 0),
('tic_tac', 'Tic Tac', 0, 0, 1),
('ticket_250', '$250 Lottery Ticket', 0, 0, 0),
('ticket_50', '$50 Lottery Ticket', 0, 0, 0),
('ticket_500', '$500 Lottery Ticket', 0, 0, 0),
('tiger_rockfish_dark_version', 'Tiger Rockfish (Dark Version)', 0, 0, 0),
('tiger_rockfish_pink_version', 'Tiger Rockfish (Pink Version)', 0, 0, 0),
('tint_meter', 'Tint Meter', 0, 0, 0),
('tire_wall', 'Tire Wall', 0, 0, 0),
('titanium_bar', 'Titanium Bar', 0, 0, 0),
('titanium_nugget', 'Titanium Nugget', 0, 0, 0),
('titanium_ore', 'Titanium Ore', 0, 0, 0),
('titanium_rod', 'Titanium Rod', 0, 0, 0),
('tnt_block', 'TNT Block', 0, 0, 0),
('tobacco_leaf', 'Tobacco Leaf', 0, 0, 0),
('tofu', 'Tofu', 0, 0, 1),
('tofu_cubes', 'Tofu Cubes', 0, 0, 1),
('tomato_juice', 'Tomato Juice', 0, 0, 1),
('tomato_sauce', 'Tomato Sauce', 0, 0, 1),
('torch', 'Torch', 0, 0, 0),
('tostada', 'Tostada', 0, 0, 1),
('tourniquet', 'Tourniquet', 0, 0, 0),
('towel', 'Towel', 0, 0, 0),
('trading_card', 'Trading Card', 0, 0, 0),
('trading_card_pack', 'Trading Cards Pack', 0, 0, 0),
('traffic_barrel', 'Traffic Barrel', 0, 0, 0),
('traffic_barrier', 'Traffic Barrier', 0, 0, 0),
('train_pass', 'Train Pass', 0, 0, 0),
('train_pass_appreciated_tier', 'Appreciated Tier', 0, 0, 0),
('train_pass_god_tier', 'God Tier', 0, 0, 0),
('train_pass_heroic_tier', 'Heroic Tier', 0, 0, 0),
('train_pass_legendary_tier', 'Legendary Tier', 0, 0, 0),
('train_pass_respected_tier', 'Respected Tier', 0, 0, 0),
('treasure_map', 'Treasure Map', 0, 0, 0),
('treasure_map_piece', 'Treasure Map Piece', 0, 0, 0),
('treefish', 'Treefish', 0, 0, 0),
('trigger', 'Trigger', 0, 0, 0),
('tube_light', 'Tube Light', 0, 0, 0),
('tuner_chip', 'Tuner Chip', 0, 0, 0),
('tungsten_bar', 'Tungsten Bar', 0, 0, 0),
('tungsten_nugget', 'Tungsten Nugget', 0, 0, 0),
('tungsten_ore', 'Tungsten Ore', 0, 0, 0),
('tungsten_plate', 'Tungsten Plate', 0, 0, 0),
('tv_remote', 'TV Remote', 0, 0, 0),
('tv_stand', 'TV Stand', 0, 0, 0),
('twitter_verification', 'Twitter Verification', 0, 0, 0),
('umbrella', 'Umbrella', 0, 0, 0),
('uncooked_ramen', 'Uncooked Ramen', 0, 0, 1),
('uncooked_rice', 'Uncooked Rice', 0, 0, 1),
('valve', 'Valve', 0, 0, 0),
('vanilla_ice_cream', 'Vanilla Ice Cream', 0, 0, 1),
('vanilla_milkshake', 'Vanilla Milkshake', 0, 0, 1),
('vape', 'Geek Bar', 0, 0, 0),
('vegan_sandwich', 'Vegan Sandwich', 0, 0, 1),
('veggie_burger', 'Veggie Burger', 0, 0, 1),
('vehicle_tracker', 'Vehicle Tracker', 0, 0, 0),
('vermilion_rockfish', 'Vermilion Rockfish', 0, 0, 0),
('vision_goggles', 'Visionary Pro Goggles', 0, 0, 0),
('vodka', 'Vodka', 0, 0, 1),
('vulcanized_rubber', 'Vulcanized Rubber', 0, 0, 0),
('wallet', 'Wallet', 0, 0, 0),
('watch', 'Watch', 0, 0, 0),
('water', 'Water', 0, 0, 1),
('watermelon', 'Watermelon', 0, 0, 1),
('weapon_acidpackage', 'Acid Package', 0, 0, 0),
('weapon_addon_1911', '1911 Kimber Tactical', 1, 0, 0),
('weapon_addon_357mag', '357 Magnum', 1, 0, 0),
('weapon_addon_680', 'Remington 680', 1, 0, 0),
('weapon_addon_6kh4', '6KH4', 1, 0, 0),
('weapon_addon_ak74', 'AK-74', 1, 0, 0),
('weapon_addon_ar15', 'AR-15', 1, 0, 0),
('weapon_addon_axmc', 'AXMC', 1, 0, 0),
('weapon_addon_berserker', 'Berserker', 1, 0, 0),
('weapon_addon_colt', 'Colt 1851 Navy', 1, 0, 0),
('weapon_addon_ddm4v7', 'DDM4V7', 1, 0, 0),
('weapon_addon_dp9', 'D&P 9 Pistol', 1, 0, 0),
('weapon_addon_dutypistol', 'SIG Sauer P226', 1, 0, 0),
('weapon_addon_endurancepistol', 'Endurance Pistol', 1, 0, 0),
('weapon_addon_fn509', 'FN-509', 1, 0, 0),
('weapon_addon_g36c', 'Heckler & Koch G36C', 1, 0, 0),
('weapon_addon_garand', 'M1 Garand', 1, 0, 0),
('weapon_addon_gardonepistol', 'Gardone Pistol', 1, 0, 0),
('weapon_addon_glock', 'Glock 19', 1, 0, 0),
('weapon_addon_glock18c', 'Glock 18C', 1, 0, 0),
('weapon_addon_hk416', 'H&K 416', 1, 0, 0),
('weapon_addon_hk433', 'H&K 433', 1, 0, 0),
('weapon_addon_honey', 'Honey Badger', 1, 0, 0),
('weapon_addon_huntingrifle', 'Hunting Rifle', 1, 0, 0),
('weapon_addon_jericho', 'Jericho 941', 1, 0, 0),
('weapon_addon_m6ic', 'LWRC M6IC', 1, 0, 0),
('weapon_addon_m870', 'Remington M870', 1, 0, 0),
('weapon_addon_m9a3', 'Beretta M9A3', 1, 0, 0),
('weapon_addon_mcx', 'SIG MCX', 1, 0, 0),
('weapon_addon_mk18', 'MK18', 1, 0, 0),
('weapon_addon_mp9', 'B&T MP9', 1, 0, 0),
('weapon_addon_multitool', 'Multi Tool', 1, 0, 0),
('weapon_addon_p320b', 'P320', 1, 0, 0),
('weapon_addon_pp19', 'PP-19 Vityaz', 1, 0, 0),
('weapon_addon_rc4', 'Remington R4-C', 1, 0, 0),
('weapon_addon_reaper', 'Reaper', 1, 0, 0),
('weapon_addon_rpk16', 'RPK-16', 1, 0, 0),
('weapon_addon_sentinelbbshotgun', 'Beanbag Shotgun', 1, 0, 0),
('weapon_addon_sentinelshotgun', 'Sentinel Shotgun', 1, 0, 0),
('weapon_addon_stidvc', 'STI DVC 2011', 1, 0, 0),
('weapon_addon_stungun', 'Coil Stun Gun', 1, 0, 0),
('weapon_addon_svd', 'SVD Dragunov', 1, 0, 0),
('weapon_addon_tacknife', 'Ultimate Tactical Knife', 1, 0, 0),
('weapon_addon_tennisball', 'Tennis Ball', 0, 0, 0),
('weapon_addon_vandal', 'RGX Vandal', 1, 0, 0),
('weapon_addon_vfcombatpistol', 'VF Combat Pistol', 1, 0, 0),
('weapon_advancedrifle', 'Advanced Rifle', 1, 0, 0),
('weapon_appistol', 'AP Pistol', 1, 0, 0),
('weapon_assaultrifle', 'Assault Rifle', 1, 0, 0),
('weapon_assaultrifle_mk2', 'Assault Rifle Mk II', 1, 0, 0),
('weapon_assaultshotgun', 'Assault Shotgun', 1, 0, 0),
('weapon_assaultsmg', 'Assault SMG', 1, 0, 0),
('weapon_autoshotgun', 'Sweeper Shotgun', 1, 0, 0),
('weapon_ball', 'Baseball', 0, 0, 0),
('weapon_bat', 'Baseball Bat', 1, 0, 0),
('weapon_battleaxe', 'Battle Axe', 1, 0, 0),
('weapon_battlerifle', 'Battle Rifle', 1, 0, 0),
('weapon_bottle', 'Broken Bottle', 1, 0, 0),
('weapon_bullpuprifle', 'Bullpup Rifle', 1, 0, 0),
('weapon_bullpuprifle_mk2', 'Bullpup Rifle Mk II', 1, 0, 0),
('weapon_bullpupshotgun', 'Bullpup Shotgun', 1, 0, 0),
('weapon_bzgas', 'BZ Gas', 0, 0, 0),
('weapon_candycane', 'Candy Cane', 1, 0, 0),
('weapon_carbinerifle', 'Carbine Rifle', 1, 0, 0),
('weapon_carbinerifle_mk2', 'Carbine Rifle Mk II', 1, 0, 0),
('weapon_ceramicpistol', 'Ceramic Pistol', 1, 0, 0),
('weapon_combatmg', 'Combat MG', 1, 0, 0),
('weapon_combatmg_mk2', 'Combat MG Mk II', 1, 0, 0),
('weapon_combatpdw', 'Combat PDW', 1, 0, 0),
('weapon_combatpistol', 'Combat Pistol', 1, 0, 0),
('weapon_combatshotgun', 'Combat Shotgun', 1, 0, 0),
('weapon_compactlauncher', 'Compact Grenade', 1, 0, 0),
('weapon_compactrifle', 'Compact Rifle', 1, 0, 0),
('weapon_crowbar', 'Crowbar', 1, 0, 0),
('weapon_dagger', 'Antique Cavalry Dagger', 1, 0, 0),
('weapon_dbshotgun', 'Double Barrel Shotgun', 1, 0, 0),
('weapon_doubleaction', 'Double Action Revolver', 1, 0, 0),
('weapon_emplauncher', 'Compact EMP Launcher', 1, 0, 0),
('weapon_fertilizercan', 'Fertilizer Can', 1, 0, 0),
('weapon_fireextinguisher', 'Fire Extinguisher', 1, 0, 0),
('weapon_firework', 'Firework Launcher', 1, 0, 0),
('weapon_flare', 'Flare', 0, 0, 0),
('weapon_flaregun', 'Flare Gun', 1, 0, 0),
('weapon_flashlight', 'Flashlight', 1, 0, 0),
('weapon_gadgetpistol', 'Perico Pistol', 1, 0, 0),
('weapon_golfclub', 'Golf Club', 1, 0, 0),
('weapon_grenade', 'Grenade', 0, 0, 0),
('weapon_grenadelauncher', 'Grenade Launcher', 1, 0, 0),
('weapon_grenadelauncher_smoke', 'Grenade Launcher Smoke', 1, 0, 0),
('weapon_gusenberg', 'Gusenberg Sweeper', 1, 0, 0),
('weapon_hackingdevice', 'Hacking Device', 1, 0, 0),
('weapon_hammer', 'Hammer', 1, 0, 0),
('weapon_hatchet', 'Hatchet', 1, 0, 0),
('weapon_hazardcan', 'Hazardous Jerry Can', 1, 0, 0),
('weapon_heavypistol', 'Heavy Pistol', 1, 0, 0),
('weapon_heavyrifle', 'Heavy Rifle', 1, 0, 0),
('weapon_heavyshotgun', 'Heavy Shotgun', 1, 0, 0),
('weapon_heavysniper', 'Heavy Sniper', 1, 0, 0),
('weapon_heavysniper_mk2', 'Heavy Sniper Mk II', 1, 0, 0),
('weapon_hominglauncher', 'Homing Launcher', 1, 0, 0),
('weapon_knife', 'Knife', 1, 0, 0),
('weapon_knuckle', 'Brass Knuckles', 1, 0, 0),
('weapon_license', 'Weapons License', 0, 0, 0),
('weapon_machete', 'Machete', 1, 0, 0),
('weapon_machinepistol', 'Machine Pistol', 1, 0, 0),
('weapon_marksmanpistol', 'Marksman Pistol', 1, 0, 0),
('weapon_marksmanrifle', 'Marksman Rifle', 1, 0, 0),
('weapon_marksmanrifle_mk2', 'Marksman Rifle Mk II', 1, 0, 0),
('weapon_mg', 'MG', 1, 0, 0),
('weapon_microsmg', 'Micro SMG', 1, 0, 0),
('weapon_militaryrifle', 'Military Rifle', 1, 0, 0),
('weapon_minigun', 'Minigun', 1, 0, 0),
('weapon_minismg', 'Mini SMG', 1, 0, 0),
('weapon_molotov', 'Molotov Cocktail', 0, 0, 0),
('weapon_musket', 'Musket', 1, 0, 0),
('weapon_navyrevolver', 'Navy Revolver', 1, 0, 0),
('weapon_nightstick', 'Nightstick', 1, 0, 0),
('weapon_petrolcan', 'Jerry Can', 1, 0, 0),
('weapon_pipebomb', 'Pipe Bombs', 0, 0, 0),
('weapon_pistol', 'Pistol', 1, 0, 0),
('weapon_pistol_mk2', 'Pistol Mk II', 1, 0, 0),
('weapon_pistol50', 'Pistol .50', 1, 0, 0),
('weapon_pistolxm3', 'WM 29 Pistol', 1, 0, 0),
('weapon_poolcue', 'Pool Cue', 1, 0, 0),
('weapon_precisionrifle', 'Precision Rifle', 1, 0, 0),
('weapon_proxmine', 'Proximity Mines', 0, 0, 0),
('weapon_pumpshotgun', 'Pump Shotgun', 1, 0, 0),
('weapon_pumpshotgun_mk2', 'Pump Shotgun Mk II', 1, 0, 0),
('weapon_railgun', 'Railgun', 1, 0, 0),
('weapon_railgunxm3', 'Coil Railgun', 1, 0, 0),
('weapon_raycarbine', 'Unholy Hellbringer', 1, 0, 0),
('weapon_rayminigun', 'Widowmaker', 1, 0, 0),
('weapon_raypistol', 'Up-n-Atomizer', 1, 0, 0),
('weapon_revolver', 'Heavy Revolver', 1, 0, 0),
('weapon_revolver_mk2', 'Heavy Revolver Mk II', 1, 0, 0),
('weapon_rpg', 'RPG', 1, 0, 0),
('weapon_sawnoffshotgun', 'Sawed-Off Shotgun', 1, 0, 0),
('weapon_smg', 'SMG', 1, 0, 0),
('weapon_smg_mk2', 'SMG Mk II', 1, 0, 0),
('weapon_smokegrenade', 'Smoke Grenade', 0, 0, 0),
('weapon_sniperrifle', 'Sniper Rifle', 1, 0, 0),
('weapon_snowball', 'Snowballs', 0, 0, 0),
('weapon_snowlauncher', 'Snowball Launcher', 1, 0, 0),
('weapon_snspistol', 'SNS Pistol', 1, 0, 0),
('weapon_snspistol_mk2', 'SNS Pistol Mk II', 1, 0, 0),
('weapon_specialcarbine', 'Special Carbine', 1, 0, 0),
('weapon_specialcarbine_mk2', 'Special Carbine Mk II', 1, 0, 0),
('weapon_stickybomb', 'Sticky Bomb', 0, 0, 0),
('weapon_stinger', 'RPG', 1, 0, 0),
('weapon_stone_hatchet', 'Stone Hatchet', 1, 0, 0),
('weapon_stungun', 'Stun Gun', 1, 0, 0),
('weapon_stungun_mp', 'Stun Gun (MP)', 1, 0, 0),
('weapon_stunrod', 'The Shocker', 1, 0, 0),
('weapon_switchblade', 'Switchblade', 1, 0, 0),
('weapon_tacticalrifle', 'Service Carbine', 1, 0, 0),
('weapon_tecpistol', 'Tactical SMG', 1, 0, 0),
('weapon_unarmed', 'Fist', 1, 0, 0),
('weapon_vintagepistol', 'Vintage Pistol', 1, 0, 0),
('weapon_wrench', 'Pipe Wrench', 1, 0, 0),
('weather_spell_rain', 'Weather Spell (Rain)', 0, 0, 0),
('weather_spell_snow', 'Weather Spell (Snow)', 0, 0, 0),
('weather_spell_thunder', 'Weather Spell (Thunder)', 0, 0, 0),
('weed_1oz', 'Weed 1oz', 0, 1, 0),
('weed_1q', 'Weed 1q', 0, 1, 0),
('weed_bud', 'Weed Bud', 0, 1, 0),
('weed_gummies', 'Weed Gummies', 0, 0, 1),
('weed_seeds', 'Weed Seeds', 0, 0, 0),
('wheel_clamp', 'Wheel Clamp', 0, 0, 0),
('whiskey', 'Whiskey', 0, 0, 1),
('widow_rockfish', 'Widow Rockfish', 0, 0, 0),
('wine', 'Wine', 0, 0, 1),
('winner_trophy', 'Winner Trophy', 0, 0, 0),
('wires', 'Wires', 0, 0, 0),
('wonder_waffle', 'Wonder Waffle', 0, 0, 1),
('wood', 'Wood', 0, 0, 0),
('xbox_controller', 'XBOX Controller', 0, 0, 0),
('yeast_packet', 'Yeast Packet', 0, 0, 0),
('yelloweye_rockfish_adult', 'Yelloweye Rockfish (Adult)', 0, 0, 0),
('yelloweye_rockfish_juvenile', 'Yelloweye Rockfish (Juvenile)', 0, 0, 0),
('yellowtail_rockfish', 'Yellowtail Rockfish', 0, 0, 0),
('yoga_mat', 'Yoga Mat', 0, 0, 0),
('zinc', 'Zinc', 0, 0, 0),
('zombie_pill', 'Zombie Pill', 0, 0, 0);

-- --------------------------------------------------------

--
-- Table structure for table `login`
--

CREATE TABLE `login` (
  `character_id` int(11) NOT NULL,
  `password` longtext NOT NULL,
  `reset_passphrase` longtext DEFAULT NULL,
  `reset_passphrase_date` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `logs`
--

CREATE TABLE `logs` (
  `logId` int(11) NOT NULL,
  `note` longtext NOT NULL,
  `timestamp` datetime NOT NULL,
  `loggedBy` int(11) NOT NULL,
  `data` longtext NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `penal_code_charges`
--

CREATE TABLE `penal_code_charges` (
  `charge_id` int(11) NOT NULL,
  `title` int(11) DEFAULT NULL,
  `label` varchar(50) NOT NULL,
  `name` varchar(50) NOT NULL,
  `type` varchar(50) NOT NULL,
  `definition` longtext NOT NULL,
  `time` int(11) NOT NULL,
  `fine` int(11) NOT NULL,
  `result` varchar(50) NOT NULL,
  `points` int(11) DEFAULT NULL,
  `added_date_time` datetime DEFAULT NULL,
  `deleted` tinyint(4) DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

--
-- Dumping data for table `penal_code_charges`
--

INSERT INTO `penal_code_charges` (`charge_id`, `title`, `label`, `name`, `type`, `definition`, `time`, `fine`, `result`, `points`, `added_date_time`, `deleted`) VALUES
(1, 2, 'P.C. 201', 'Criminal Threat', 'Misdemeanor', 'Intentionally puts another in the belief of physical harm or offensive contact.', 10, 300, '-', NULL, '2023-07-30 05:27:42', 0),
(2, 2, 'P.C. 202', 'Assault and Battery', 'Felony', 'Uses violence to cause physical harm to another person without a weapon.', 20, 800, '-', NULL, '2023-07-30 05:27:42', 0),
(3, 2, 'P.C. 9999', 'Aggravated Assault and Battery', 'Felony', 'Uses violence to cause physical harm to another person with a weapon.', 40, 1000, 'Seize', NULL, '2023-07-30 05:27:42', 1),
(4, 2, 'P.C. 205', 'Torture', 'Felony', 'Causes extreme pain and suffering to another person.', 70, 1200, 'Seize', NULL, '2023-07-30 05:27:42', 0),
(5, 2, 'P.C. 207', 'Terroristic Threat', 'Felony', 'Intentionally puts another in the belief or fear of an act of terrorism happening.', 30, 1000, 'Seize', NULL, '2023-07-30 05:27:42', 0),
(6, 2, 'P.C. 208', 'Terrorism', 'Felony', 'A violent, criminal act committed by a person to further goals stemming from political, religious, social, or environmental influences.', 0, 0, 'Seize', NULL, '2023-07-30 05:27:42', 0),
(7, 2, 'P.C. 9999', 'Attempted Murder', 'Felony', 'Attempts to perform a premeditated killing of another person with malice.', 80, 1500, 'Seize', NULL, '2023-07-30 05:27:42', 1),
(8, 2, 'P.C. 209', 'Involuntary Manslaughter', 'Felony', 'Acted recklessly and negligently which resulted in the death of another person.', 0, 0, 'Seize', NULL, '2023-07-30 05:27:42', 0),
(9, 2, 'P.C. 210', 'Voluntary Manslaughter', 'Felony', 'Acted in the heat of passion caused by being reasonably and strongly provoked which resulted in the death of another person.', 0, 0, 'Seize', NULL, '2023-07-30 05:27:42', 0),
(10, 2, 'P.C. 211', 'Second Degree Murder', 'Felony', 'The unlawful killing of another person without prior planning, occurring as a result of reckless or intentional violence where death was a foreseeable consequence.', 0, 0, 'Seize', NULL, '2023-07-30 05:27:42', 0),
(11, 2, 'P.C. 212', 'First Degree Murder', 'Felony', 'The intentional and premeditated killing of another person, carried out with malice and a clear, deliberate intent to cause death.', 0, 0, 'Seize', NULL, '2023-07-30 05:27:42', 0),
(12, 2, 'P.C. 213', 'False Imprisonment', 'Misdemeanor', 'A person who intentionally and unlawfully restrains, detains, or confines another person.', 10, 600, '-', NULL, '2023-07-30 05:27:42', 0),
(13, 2, 'P.C. 214', 'Kidnapping', 'Felony', 'Intentionally took another person from point A to point B without consent.', 50, 1000, 'Seize', NULL, '2023-07-30 05:27:42', 0),
(14, 3, 'P.C. 301', 'Loitering', 'Misdemeanor', 'Fails to leave property when asked to do so by a relevant representative of the property.', 10, 250, '-', NULL, '2023-07-30 05:27:42', 0),
(15, 3, 'P.C. 302', 'Trespassing', 'Misdemeanor', 'Enters, or remains on land and fails to leave after being ordered to leave or which noted that entry was forbidden', 10, 300, '-', NULL, '2023-07-30 05:27:42', 0),
(16, 3, 'P.C. 9990', 'Trespassing on Government Property', 'Felony', 'Trespasses specifically on Government Property.', 15, 950, '-', NULL, '2023-07-30 05:27:42', 1),
(17, 3, 'P.C. 303', 'Burglary', 'Felony', 'The act of entering property with the intent to commit a crime. For vehicles specifically, this is known as Auto-Burglary.', 25, 600, 'Seize', NULL, '2023-07-30 05:27:42', 0),
(18, 3, 'P.C. 304', 'Robbery', 'Felony', 'The unlawful taking of property from the person of another through the use of threat or force.', 25, 400, 'Seize', NULL, '2023-07-30 05:27:42', 0),
(19, 3, 'P.C. 305', 'Armed Robbery', 'Felony', 'The unlawful taking of property from the person of another by the use of a weapon.', 40, 850, 'Seize', NULL, '2023-07-30 05:27:42', 0),
(20, 3, 'P.C. 306', 'Robbery of a Shop', 'Felony', 'The unlawful taking of property within a store.', 40, 1000, 'Seize', NULL, '2023-07-30 05:27:42', 0),
(21, 3, 'P.C. 307', 'Robbery of a Bank', 'Felony', 'The unlawful taking of property within a bank.', 80, 2500, 'Seize', NULL, '2023-07-30 05:27:42', 0),
(22, 3, 'P.C. 308', 'Robbery of a Stockade', 'Felony', 'The unlawful taking of property within a Stockade or armored vehicle.', 110, 3000, 'Seize', NULL, '2023-07-30 05:27:42', 0),
(23, 3, 'P.C. 309', 'Robbery of a Jewellery Store', 'Felony', 'The unlawful taking of property within a Jewellery Store.', 140, 3500, 'Seize', NULL, '2023-07-30 05:27:42', 0),
(24, 3, 'P.C. 310', 'Theft', 'Misdemeanor', 'Takes personal property of another without permission or consent.', 10, 200, 'Per', NULL, '2023-07-30 05:27:42', 0),
(25, 3, 'P.C. 311', 'Grand Theft', 'Felony', 'Taking the property of another illegally with the intent to deprive the owner of that property. Value exceeding $3000.', 15, 1000, 'Per', NULL, '2023-07-30 05:27:42', 0),
(26, 3, 'P.C. 312', 'Grand Theft Auto', 'Felony', 'Taking the vehicle of another illegally with the intent to deprive the owner of that vehicle.', 30, 1000, '-', NULL, '2023-07-30 05:27:42', 0),
(27, 3, 'P.C. 313', 'Destruction of Private Property', 'Misdemeanor', 'Willful destruction or damaging of property in a manner that defaces, mars, or otherwise adds a physical blemish.', 10, 350, '-', NULL, '2023-07-30 05:27:42', 0),
(28, 3, 'P.C. 314', 'Possession of Stolen Property', 'Misdemeanor', 'Has possession of property not belonging to them and the owner has reported said items stolen.', 10, 350, 'Per, Seize', NULL, '2023-07-30 05:27:42', 0),
(29, 3, 'P.C. 315', 'Receiving Stolen Property', 'Felony', 'Individual has accepted possession of goods or property and knew they were stolen.', 25, 400, '-', NULL, '2023-07-30 05:27:42', 0),
(30, 3, 'P.C. 9999', 'Extortion', 'Felony', 'The unlawful taking of money or property through intimidation.', 50, 900, '-', NULL, '2023-07-30 05:27:42', 1),
(31, 3, 'P.C. 316', 'Corruption', 'Felony', 'Improper and unlawful conduct by abusing one\'s position of power in a way intended to secure a benefit for oneself or another.', 55, 1100, '-', NULL, '2023-07-30 05:27:42', 0),
(32, 3, 'P.C. 317', 'Fraud', 'Felony', 'The deliberate misrepresentation of fact for the purpose of depriving someone of a valuable possession.', 20, 450, '-', NULL, '2023-07-30 05:27:42', 0),
(33, 3, 'P.C. 318', 'Forgery', 'Felony', 'Making and/or possession of a false writing with an intent to defraud.', 30, 600, '-', NULL, '2023-07-30 05:27:42', 0),
(34, 3, 'P.C. 319', 'Vandalism', 'Misdemeanor', 'The willful or malicious destruction or defacement of property with malicious intent.', 10, 300, 'Seize', NULL, '2023-07-30 05:27:42', 0),
(35, 3, 'P.C. 320', 'Arson', 'Felony', 'Starts a fire or causing an explosion with the intent to cause damage after ignition.', 20, 600, 'Seize', NULL, '2023-07-30 05:27:42', 0),
(36, 3, 'P.C. 321', 'Animal Abuse', 'Felony', 'The act of intentionally harming dogs, cats, and birds (does not include wild animals).', 20, 600, 'Seize', NULL, '2023-07-30 05:27:42', 0),
(37, 3, 'P.C. 323', 'Hunting Without a License', 'Felony', 'The act of operating a weapon designated for hunting without a proper license.', 50, 1500, 'Seize', NULL, '2023-07-30 05:27:42', 0),
(38, 3, 'P.C. 324', 'Possession of Contraband', 'Misdemeanor', 'Has possession of 1-10 red, blue, or green decryption keys, 1-10 chips, 1-10 raspberry chips, 1-10 fake plates, 1-10 meth tables, 1-10 catalytic converters or 1-10 pagers.', 10, 150, 'Per, Seize', NULL, '2023-07-30 05:27:42', 0),
(39, 3, 'P.C. 326', 'Possession of Contraband in Crime', 'Felony', 'Has possession of 1-10 thermite, 1-10 lockpicks, 1-10 tuner chips, 1-10 fake plates, 1-10 boosting tablets, 1-10 meth table, 1-10 acetone, 1-10 lithium batteries, 1-10 sawzalls, or 1-10 pagers, and uses it to aid in a crime specific to the contraband that they are being charged for.', 15, 200, 'Per, Seize', NULL, '2023-07-30 05:27:42', 0),
(40, 3, 'P.C. 328', 'Breaching Company Regulations', 'Misdemeanor', 'Intentionally disregarded or breached any of the official company regulations set by the government.', 10, 4000, 'Per, Seize', NULL, '2023-07-30 05:27:42', 0),
(41, 3, 'P.C. 9999', 'Damaging a Communication Device', 'Misdemeanor', 'Individual removes, destroys, or obstructs the use of any wireless communication device with the intent to prevent help.', 40, 600, 'Seize', NULL, '2023-07-30 05:27:42', 1),
(42, 4, 'P.C. 401', 'Disorderly Conduct', 'Misdemeanor', 'A person who intentionally disturbs the public peace and order by language or other conduct.', 10, 400, '-', NULL, '2023-07-30 05:27:42', 0),
(43, 4, 'P.C. 9999', 'Indecent Exposure', 'Felony', 'A person commits indecent exposure if that person exposes their genitals in any place a reasonable person would deem public.', 20, 500, '-', NULL, '2023-07-30 05:27:42', 1),
(44, 5, 'P.C. 501', 'Bribery', 'Felony', 'The act of promising to or exchanging property with the corrupt aim of influencing a public official in the discharge of their official duties.', 25, 500, '-', NULL, '2023-07-30 05:27:42', 0),
(45, 5, 'P.C. 502', 'Disregarding a Lawful Command', 'Misdemeanor', 'The act of ignoring or disregarding a command given by a peace officer to achieve a reasonable and lawful goal.', 10, 300, '-', NULL, '2023-07-30 05:27:42', 0),
(46, 5, 'P.C. 503', 'Impersonation of a Public Servant', 'Felony', 'The false representation by one person that they are another or that they occupies the position a public servant.', 20, 500, '-', NULL, '2023-07-30 05:27:42', 0),
(47, 5, 'P.C. 504', 'Impersonation of a Peace Officer', 'Felony', 'The false representation by one person that they are another or that they occupies the position a peace officer.', 30, 900, '-', NULL, '2023-07-30 05:27:42', 0),
(48, 5, 'P.C. 505', 'Obstruction of Justice', 'Misdemeanor', 'An act that \"corruptly or by threats or force, or by any threatening letter or communication obstructs the due administration of justice.\"', 10, 450, '-', NULL, '2023-07-30 05:27:42', 0),
(49, 5, 'P.C. 506', 'Resisting a Peace Officer', 'Misdemeanor', 'A person who avoids or resists apprehension.', 20, 600, '-', NULL, '2023-07-30 05:27:42', 0),
(50, 5, 'P.C. 507', 'Felony Resisting a Peace Officer', 'Felony', 'A person who avoids or resists apprehension with an attempt or threat to use physical violence.', 30, 1000, '-', NULL, '2023-07-30 05:27:42', 0),
(51, 5, 'P.C. 508', 'Misuse of a Mobile Hotline', 'Misdemeanor', 'A person who intentionally uses the Government, Police or EMS Hotline for other reasons than emergency purposes.', 5, 500, '-', NULL, '2023-07-30 05:27:42', 0),
(52, 5, 'P.C. 509', 'Tampering with Evidence', 'Felony', 'Alters evidence by any form with intent to mislead a public servant who is or may be engaged in such proceeding or investigation.', 50, 2000, '-', NULL, '2023-07-30 05:27:42', 0),
(53, 5, 'P.C. 510', 'Unlawful Arrest', 'Felony', 'The intentional detention by one person of another without probable cause, a valid arrest warrant, or consent.', 35, 750, '-', NULL, '2023-07-30 05:27:42', 0),
(54, 5, 'P.C. 511', 'Contempt of Court', 'Misdemeanor', 'Any form of disturbance that may impede the functioning of the court. The punishment may be greater depending on the severity of disturbance.', 20, 500, '-', NULL, '2023-07-30 05:27:42', 0),
(55, 5, 'P.C. 512', 'Breach of Contract', 'Misdemeanor', 'Any form of failure to the terms of a legally binding contract.', 10, 1000, '-', NULL, '2023-07-30 05:27:42', 0),
(56, 5, 'P.C. 513', 'Violation of a Court Order', 'Felony', 'Any form of violation of a legally binding contract presented by a Judge.', 30, 1400, '-', NULL, '2023-07-30 05:27:42', 0),
(57, 5, 'P.C. 514', 'Wearing a Disguise to Evade Police', 'Misdemeanor', 'Wearing a mask or disguise to evade recognitition or identification in the commission of a crime, or escape when charged with a crime.', 0, 800, '-', NULL, '2023-07-30 05:27:42', 0),
(58, 6, 'P.C. 9999', 'Disturbing the Peace', 'Misdemeanor', 'Unreasonably disrupts the public tranquillity or has a strong tendency to cause a disturbance.', 0, 350, '-', NULL, '2023-07-30 05:27:42', 1),
(59, 6, 'P.C. 601', 'Incitement to Riot', 'Misdemeanor', 'Conduct, words, or other means that urge or naturally lead others to riot, violence, or insurrection.', 10, 450, '-', NULL, '2023-07-30 05:27:42', 0),
(60, 6, 'P.C. 602', 'Public Intoxication', 'Misdemeanor', 'Being in any area that is not private while under the influence of alchohol and/or drugs.', 5, 300, 'Seize', NULL, '2023-07-30 05:27:42', 0),
(61, 6, 'P.C. 603', 'Public Endangerment', 'Felony', 'Any person who recklessly engages in conduct which places or may place another person in danger of death or serious bodily injury.', 20, 400, 'Seize', NULL, '2023-07-30 05:27:42', 0),
(62, 6, 'P.C. 604', 'Verbal Harassment', 'Misdemeanor', 'A person with intent to harass, annoy or alarm another with the use of speech.', 10, 300, '-', NULL, '2023-07-30 05:27:42', 0),
(63, 6, 'P.C. 9999', 'Sexual Harassment', 'Felony', 'A person with intent to sexually harass another with the use of speech of sexual nature.', 0, 1000000, '-', NULL, '2023-07-30 05:27:42', 1),
(64, 6, 'P.C. 605', 'Civil Negligence', 'Misdemeanor', 'Conduct which falls below a standard which a reasonable person would deem safe.', 10, 400, '-', NULL, '2023-07-30 05:27:42', 0),
(65, 6, 'P.C. 606', 'Criminal Negligence', 'Felony', 'Conduct which falls below a standard which a reasonable person would deem safe with the intent to harm another person.', 20, 500, 'Seize', NULL, '2023-07-30 05:27:42', 0),
(66, 7, 'P.C. 701', 'Maintaining a Place for Distribution', 'Misdemeanor', 'Having keys to a property for the purpose of selling, giving away, storing, or using any Class B substance without a sales permit, Class A substance, narcotics, contraband or illegal weapons.', 25, 600, 'Seize', NULL, '2023-07-30 05:27:42', 0),
(67, 7, 'P.C. 703', 'Sale of a Controlled Substance', 'Felony', 'The act of offering, selling, transporting, or giving away narcotics, a Class B Substance or Class A Substance to another person without a sales permit.', 20, 400, 'Seize', NULL, '2023-07-30 05:27:42', 0),
(68, 7, 'P.C. 704', 'Possession of a Class B Substance', 'Misdemeanor', 'Possession of 11-24 joints without a sales permit, 1-19q of processed or unprocessed weed (4q=1oz), 1-4 bud of weed, 1-4 acid, or 1-6 lean.', 5, 200, 'Per, Seize', NULL, '2023-07-30 05:27:42', 0),
(69, 7, 'P.C. 705', 'Intention to Sell a Class B Substance', 'Felony', 'Possession of 16-24 joints without a sales permit, 5-19q of processed or unprocessed weed (4q=1oz), 3-4 acid, or 4-6 lean.', 30, 1400, 'Seize', NULL, '2023-07-30 05:27:42', 1),
(70, 7, 'P.C. 705', 'Drug Trafficking of a Class B Substance', 'Felony', 'Possession of 25 or more joints without a sales permit, 20q or more of processed or unprocessed weed (4q=1oz) 5 or more buds of weed, 5 or more acid, or 7 or more lean.', 50, 3500, 'Seize', NULL, '2023-07-30 05:27:42', 0),
(71, 7, 'P.C. 706', 'Possession of a Class A Substance', 'Felony', 'Possession of 1-7 bags of cocaine, 1-7 bags of meth, or 1-4 shrooms.', 10, 500, 'Per, Seize', NULL, '2023-07-30 05:27:42', 0),
(72, 7, 'P.C. 708', 'Intention to Sell a Class A Substance', 'Felony', 'Possession of 3-7 bags of cocaine, 3-7 bags of meth, or 3-4 shrooms.', 5, 2200, 'Seize', NULL, '2023-07-30 05:27:42', 1),
(73, 7, 'P.C. 707', 'Drug Trafficking of a Class A Substance', 'Felony', 'Possession of 1 or more bricks of cocaine, 8 or more bags of cocaine, 8 or more bags of meth, or 5 or more shrooms.', 70, 5000, 'Seize', NULL, '2023-07-30 05:27:42', 0),
(74, 7, 'P.C. 708', 'Intention to Sell Distilled Spirits', 'Misdemeanor', 'Possession of 3 or more distilled spirits, with the clear intention to sell without a license.', 5, 100, 'Per, Seize', NULL, '2023-07-30 05:27:42', 0),
(75, 7, 'P.C. 709', 'Possession of Narcotics', 'Felony', 'Possession of 1-10 narcotics without a prescription from a licensed doctor currently working with or for the EMS.', 10, 400, 'Per, Seize', NULL, '2023-07-30 05:27:42', 0),
(76, 7, 'P.C. 712', 'Mining Without a License', 'Misdemeanor', 'The activity of extracting gemstones or minerals from the ground without a mining license. ', 20, 1000, 'Seize', NULL, '2023-07-30 05:27:42', 0),
(77, 7, 'P.C. 713', 'Mining Without a Scanner', 'Misdemeanor', 'The activity of extracting gemstones or minerals from the ground without a gemstone scanner is considered civil negligence.', 15, 500, '-', NULL, '2023-07-30 05:27:42', 0),
(78, 8, 'P.C. 801', 'Driving Without a License', 'Misdemeanor', 'Operating a motor vehicle without proper identification.', 0, 300, 'Seize', 3, '2023-07-30 05:27:42', 0),
(79, 8, 'P.C. 802', 'Driving With a Suspended License', 'Misdemeanor', 'Operating a motor vehicle with a suspended license.', 10, 400, 'Seize', NULL, '2023-07-30 05:27:42', 0),
(80, 8, 'P.C. 803', 'Hit and Run', 'Felony', 'Leaving the scene of an accident while operating a vehicle. Failing to stop and render assistance if vehicular accident for which you are at fault.', 25, 750, 'Seize', 5, '2023-07-30 05:27:42', 0),
(81, 8, 'P.C. 804', 'Speeding', 'Misdemeanor', 'The act of driving over the speed limit, or greater than, or in a manner other than is reasonable and prudent for the particular location, given the conditions of traffic, weather, and road surface and having regard to the actual and potential hazards existing.', 0, 300, '-', 2, '2023-07-30 05:27:42', 0),
(82, 8, 'P.C. 805', 'Excessive Speeding', 'Felony', 'The act of driving 30+ mph over the speed limit, or greater than, or in a manner other than is reasonable and prudent for the particular location, given the conditions of traffic, weather, and road surface and having regard to the actual and potential hazards existing.', 30, 600, 'Seize', 3, '2023-07-30 05:27:42', 0),
(83, 8, 'P.C. 806', 'Reckless Driving', 'Misdemeanor', 'Operating a motor vehicle in such a manner that has a disregard of public safety.', 20, 600, '-', 4, '2023-07-30 05:27:42', 0),
(84, 8, 'P.C. 807', 'Traffic Violation', 'Misdemeanor', 'Operating a vehicle in any way with disregard to public traffic laws.', 0, 200, 'Per', 2, '2023-07-30 05:27:42', 0),
(85, 8, 'P.C. 808', 'Parking Violation', 'Misdemeanor', 'Parking of a vehicle in any area that isn\'t designated for public parking. ', 0, 200, 'Per', 2, '2023-07-30 05:27:42', 0),
(86, 8, 'P.C. 809', 'Evading a Peace Officer', 'Misdemeanor', 'A person (non-criminal) who has been given a visual or auditory signal by an officer, and willfully refuse to stop or attempts to elude the officer.', 15, 350, 'Seize', 4, '2023-07-30 05:27:42', 0),
(87, 8, 'P.C. 810', 'Felony Evading a Peace Officer', 'Felony', 'A person who has been given a visual or auditory signal by an officer, and willfully refuse to stop their motor vehicle.', 30, 700, 'Seize', 6, '2023-07-30 05:27:42', 0),
(88, 8, 'P.C. 811', 'Driving Under the Influence (DUI)', 'Felony', 'Operating a motor vehicle while under the effects of alcohol or drugs.', 10, 400, 'Seize', 10, '2023-07-30 05:27:42', 0),
(89, 8, 'P.C. 812', 'Jaywalking', 'Misdemeanor', 'Crossing any 4 lane (2 in either direction) highway/interstate without using the designated crosswalk. ', 0, 50, '-', NULL, '2023-07-30 05:27:42', 0),
(90, 8, 'P.C. 813', 'Joyriding', 'Misdemeanor', 'Operating a motor vehicle without explicit permission from the owner of a vehicle (where PC can not be established that the vehicle is stolen).', 10, 350, 'Seize', 2, '2023-07-30 05:27:42', 0),
(91, 8, 'P.C. 814', 'Unauthorized Operations of an Aircraft', 'Felony', 'Operating an aircraft without the corresponding pilot license of the aircraft being operated.', 20, 1500, 'Seize', 4, '2023-07-30 05:27:42', 0),
(92, 8, 'P.C. 815', 'Reckless Operations of an Aircraft', 'Felony', 'Operating an aircraft with disregard of public safety.', 25, 2500, 'Seize', 6, '2023-07-30 05:27:42', 0),
(93, 8, 'P.C. 817', 'Tampering with a Motor Vehicle', 'Misdemeanor', 'Injure, tamper, break, or remove any part of a vehicle, or it\'s contents, without the consent of the owner.', 15, 750, 'Per, Seize', NULL, '2023-07-30 05:27:42', 0),
(94, 9, 'P.C. 901', 'Carrying a Firearm Without a License', 'Felony', 'Act of carrying and/or concealing a firearm without proper identification/documentation to go along with it.', 25, 400, 'Seize', NULL, '2023-07-30 05:27:42', 0),
(95, 9, 'P.C. 902', 'Brandishing a Weapon', 'Misdemeanor', 'The act of openly carrying a weapon, replica, or similar object in an attempt to elicit fear.', 20, 350, 'Seize', NULL, '2023-07-30 05:27:42', 0),
(96, 9, 'P.C. 903', 'Weapons Discharge Violation', 'Misdemeanor', 'Discharging any firearm within city limits, or in Blaine County on Government Property, without a lawful reason for doing so.', 10, 200, 'Seize', NULL, '2023-07-30 05:27:42', 0),
(97, 9, 'P.C. 904', 'Felony Weapons Discharge Violation', 'Felony', 'Discharging any firearm without a lawful reason for doing so which endangers the safety of the public.', 20, 400, 'Seize', NULL, '2023-07-30 05:27:42', 0),
(98, 9, 'P.C. 905', 'Display of Tactical Gear', 'Misdemeanor', 'Act of wearing and refusing to remove any tactical vests, or holsters, in plain view of the public.', 5, 200, 'Per, Seize', NULL, '2023-07-30 05:27:42', 0),
(99, 9, 'P.C. 906', 'Possession of Unregistered Firearm', 'Felony', 'Act of carrying and/or concealing a firearm that does not have a valid serial number.', 10, 500, 'Per, Seize', NULL, '2023-07-30 05:27:42', 0),
(100, 9, 'P.C. 907', 'Possession of Class 2 Weapon', 'Felony', 'Act of carrying and/or concealing a Class 2 weapon.', 30, 1000, 'Per, Seize', NULL, '2023-07-30 05:27:42', 0),
(101, 9, 'P.C. 908', 'Possession of Class 3 Weapon', 'Felony', 'Act of carrying and/or concealing a Class 3 weapon.', 40, 2000, 'Per, Seize', NULL, '2023-07-30 05:27:42', 0),
(102, 9, 'P.C. 911', 'Trafficking of Class 2 Weapon', 'Felony', 'Possesion of 3 or more Class 2 weapons.', 150, 5000, 'Seize', NULL, '2023-07-30 05:27:42', 0),
(103, 9, 'P.C. 912', 'Trafficking of Class 3 Weapon', 'Felony', 'Possesion of 3 or more Class 3 weapons.', 200, 8000, 'Seize', NULL, '2023-07-30 05:27:42', 0),
(104, 9, 'P.C. 915', 'Possession of Extended Magazines', 'Misdemeanor', 'Any person in possession of any large-capacity magazine, including when it is attached to any weapon, is guilty of a misdemeanor. This shall not apply to a peace officer when on duty and when the use of extended magazines is authorized and is within the course and scope of their duties.', 10, 500, 'Per, Seize', NULL, '2023-07-30 05:27:42', 0),
(105, 9, 'P.C. 916', 'Possession of Silencers', 'Felony', 'Any person in possession of a silencer, including when it is attached to any weapon, is guilty of a felony. This shall not apply to a peace officer when on duty and when the use of silencers is authorized and is within the course and scope of their duties.', 30, 1500, 'Per, Seize', NULL, '2023-07-30 05:27:42', 0),
(106, 10, 'P.C. 1001', 'Racketeering', 'Felony', 'A pattern of commiting Criminal Profiteering crimes, which may include Money Laundering, Trafficking and Murder charges.', 0, 0, 'Seize', NULL, '2023-07-30 05:27:42', 0),
(107, 10, 'P.C. 1002', 'Gaming', 'Misdemeanor', 'Dealing, playing or betting at, or against, any card, banking, or percentage game with dice, cards, or any device for money, credits or other representative of value, outside of a state approved card-room or Diamond Casino.', 5, 200, 'Seize', NULL, '2023-07-30 05:27:42', 0),
(108, 5, 'P.C. 515', 'Perjury', 'Felony', 'Knowingly providing any false testimony while under oath including both written and verbal.', 50, 1500, '-', NULL, '2024-03-31 11:15:00', 0),
(109, 5, 'P.C. 516', 'Violating a Protective Order', 'Felony', 'Any intentional and knowing violation of a protective order from either party included in the order.', 50, 1500, '-', NULL, '2024-03-31 11:15:00', 0),
(110, 5, 'P.C. 517', 'Prisoner Escaping Custody.', 'Felony', 'An individual being transported by a Peace Officer, escapes custody of Law Enforcement.', 50, 1500, '-', NULL, '2024-03-31 11:15:00', 0),
(111, 5, 'P.C. 518', 'Rescuing a Prisoner', 'Felony', 'An individual who rescues or aids a prisoner in escape from lawful custody.', 100, 1500, '-', NULL, '2024-03-31 11:15:00', 0),
(112, 5, 'P.C. 519', 'Sightseeing at the Scene of an Emergency', 'Misdemeanor', 'Any person who goes to or stops at the scene of an emergency for the purpose of viewing the scene or the activities of peace officers, firefighters, or emergency medical personnel during the course of their duties at the scene; unless, it is a part of the duties of that person’s employment.', 15, 250, '-', NULL, '2024-03-31 11:15:00', 0),
(113, 7, 'P.C. 702', 'Felony Maintaining a Place for Distribution', 'Felony', 'Having keys to a property for the purpose of selling, giving away, storing illegal weapons.', 50, 1200, 'Seize', NULL, '2024-03-31 11:15:00', 0),
(114, 7, 'P.C. 9999', 'Intention to Sell Narcotics', 'Felony', 'Possession of 2-10 narcotics without a prescription from a licensed doctor currently working with or for the EMS.', 40, 1800, 'Seize', NULL, '2024-03-31 11:15:00', 1),
(115, 7, 'P.C. 710', 'Drug Trafficking of Narcotics', 'Felony', 'Possession of 11 or more narcotics without a prescription from a licensed doctor currently working with or for the EMS.', 70, 4500, 'Seize', NULL, '2024-03-31 11:15:00', 0),
(116, 7, 'P.C. 711', 'Manufacturing Controlled Substances', 'Felony', 'The manufacturing, producing, or importing of any Narcotics or Class A or B substances without a sales permit.', 35, 1000, 'Seize', NULL, '2024-03-31 11:15:00', 0),
(117, 8, 'P.C. 818', 'Engaging in a Speed Contest', 'Misdemeanor', 'Engaging in a high-speed motor vehicle race against another vehicle or vehicles.', 15, 300, 'Seize', 2, '2024-03-31 11:15:00', 0),
(1162, 2, 'P.C. 203', 'Second Degree Aggravated Assault and Battery', 'Felony', 'A spontaneous act of violence using a deadly weapon or dangerous object to cause physical harm to another person, without premeditation or intent to kill.', 40, 1000, 'Seize', NULL, NULL, 0),
(1163, 2, 'P.C. 204', 'First Degree Aggravated Assault and Battery', 'Felony', 'A premeditated and deliberate attack on another person with the intent to cause serious harm or death, where the actions go beyond aggravated assault but do not result in a completed killing.', 60, 1500, 'Seize', NULL, NULL, 0),
(1164, 2, 'P.C. 206', 'Maiming', 'Felony', 'The act of disabling, disfiguring, removing or permanantly damaging a person\'s limbs (all extremeties) either intentionally or in a fight.', 350, 4000, 'Per,Seize', NULL, NULL, 0),
(1165, 2, 'P.C. 215', 'Destructive Use of Blasting Agents', 'Felony', 'Intentionally using an incendiary/explosive device to cause harm to another person', 85, 2500, 'Seize', NULL, NULL, 0),
(1166, 3, 'P.C. 322', 'Animal Negligence', 'Felony', 'The act of intentionally putting a animal on a situation of danger that could possibly harm the animal (does not include wild animals).', 20, 700, 'Seize', NULL, NULL, 0),
(1167, 3, 'P.C. 325', 'Trafficking of Contraband', 'Felony', 'Has possession of 11 or more red, blue, or green decryption keys, 11 or more chips, 11 or more raspberry chips, 11 or more fake plates, 11 or more meth tables, 11 or more catalytic converters or 11 or more pagers.', 30, 400, 'Per, Seize', NULL, NULL, 0),
(1168, 3, 'P.C. 327', 'Trafficking of Contraband in Crime', 'Felony', 'Has possession of 11 or more thermite, 11 or more lockpicks, 11 or more tuner chips, 11 or more fake plates, 11 or more boosting tablets, 11 or more meth table, 11 or more acetone, 11 or more lithium batteries, 11 or more sawzalls, or 11 or more pagers, and uses it to aid in a crime specific to the contraband that they are being charged for.', 220, 3000, '-', NULL, NULL, 0),
(1169, 8, 'P.C. 816', 'Improper Operations of an Aircraft', 'Misdemeanor', 'Operating an aircraft in disregard of Aviation SOP\'s by not engaging on the correct radio channel or by not having the correct tools (Flight radar)', 10, 500, '-', NULL, NULL, 0),
(1170, 9, 'P.C. 909', 'Possession of Class 4 Weapon', 'Felony', 'Act of carrying and/or concealing a Class 4 weapon.', 50, 3000, 'Per,  Seize', NULL, NULL, 0),
(1171, 9, 'P.C. 910', 'Possession of Class 5 Weapon', 'Felony', 'Act of carrying and/or concealing a Class 5 weapon.', 60, 4500, 'Per,  Seize', NULL, NULL, 0),
(1172, 9, 'P.C. 913', 'Trafficking of Class 4 Weapon', 'Felony', 'Possession of 3 or more Class 4 weapons.', 250, 11000, 'Seize', NULL, NULL, 0),
(1173, 9, 'P.C. 914', 'Trafficking of Class 5 Weapon', 'Felony', 'Possession of 3 or more Class 5 weapons.', 275, 17000, 'Seize', NULL, NULL, 0);

-- --------------------------------------------------------

--
-- Table structure for table `penal_code_definitions`
--

CREATE TABLE `penal_code_definitions` (
  `definition_id` int(11) NOT NULL,
  `label` varchar(50) DEFAULT NULL,
  `value` varchar(50) DEFAULT NULL,
  `definition` longtext DEFAULT NULL,
  `added_date_time` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

--
-- Dumping data for table `penal_code_definitions`
--

INSERT INTO `penal_code_definitions` (`definition_id`, `label`, `value`, `definition`, `added_date_time`) VALUES
(2, 'P.C. 101', 'Public Servant', 'Any person employed by the EMS, BCFD, State, or the DOJ, including Bar Certified individuals, the Vice Governor, Governor, Judges and Chief Justice.', '2023-07-30 05:10:55'),
(3, 'P.C. 102', 'Peace Officer', 'Any Police Officer, State Trooper, Highway Patrol, Sheriff Deputy, County Sheriff, or Department of Corrections Officer.', '2023-07-30 05:10:55'),
(4, 'P.C. 103', 'Notary Public', 'Any person employed directly by the DOJ. This person can notarise affidavits. ', '2023-07-30 05:10:55'),
(5, 'P.C. 104', 'Reasonable Suspicion', 'A specific, justifiable suspicion that is based on specific facts or circumstances about a specific individual.', '2023-07-30 05:10:55'),
(6, 'P.C. 105', 'Probable Cause (PC)', 'Reasonable grounds for believing a person is guilty of a criminal act, allowing the search, arrest, prosecution, or trial of such a person.', '2023-07-30 05:10:55'),
(7, 'P.C. 106', 'Per', 'Any charge labelled with Per should be given once for each contraband seized.', '2023-07-30 05:10:55'),
(8, 'P.C. 107', 'Seize', 'Contraband, weapons, money, substances, and/or vehicles must be seized indefinitely if related to the crime. Do not return unless a Judge specifies otherwise.', '2023-07-30 05:10:55'),
(9, 'P.C. 108', 'Points', 'Penalty points are issued for vehicular offences. They stay on a person\'s driving record and they lose their licence if they collect more than 15.', '2023-07-30 05:10:55'),
(10, 'P.C. 109', 'Possession', 'Contraband (or replicas) having been or is on their person, in their vehicle, or in their estate.', '2023-07-30 05:10:55'),
(11, 'P.C. 110', 'Class A Substance', 'Cocaine, Methamphetamine (Meth), or Psilocybe Cyanescens (Shrooms), including synthetic alternative', '2023-07-30 05:10:55'),
(12, 'P.C. 111', 'Class B Substance', 'Marijuana (Weed), Lysergic Acid Diethylamide (Acid), or Lean, including synthetic analogue.', '2023-07-30 05:10:55'),
(13, 'P.C. 112', 'Class 1 Weapon', 'Any lethal weapon sold and manufactured by Ammu-Nation, including replicas. Full list of weaponry included is listed in the weaponry database.', '2023-07-30 05:10:55'),
(14, 'P.C. 113', 'Class 2 Weapon', 'Single Fire Pistols not manufactured by Ammu-Nation, including replicas. Full list of weaponry included is listed in the weaponry database.', '2023-07-30 05:10:55'),
(15, 'P.C. 114', 'Class 3 Weapon', 'Automatic Pistols, Submachine Guns, Shotguns, including replicas. Full list of weaponry included is listed in the weaponry database.', '2023-07-30 05:10:55'),
(16, 'P.C. 117', 'Property', 'Anything that is owned by a person or entity.', '2023-07-30 05:10:55'),
(17, 'P.C. 118', 'Government Property', 'Any property owned or issued by the Government.', '2023-07-30 05:10:55'),
(18, 'P.C. 119', 'Reporter’s Privilege', 'A “reporter” or “journalist” is protected under constitutional or statutory law, from being compelled to testify about confidential information or sources.', '2023-07-30 05:10:55'),
(19, 'P.C. 120', 'RICO', 'Racketeering Influenced and Corrupt Organizations Act.', '2023-07-30 05:10:55'),
(20, 'P.C. 121', 'HUT', 'Held Until Trial, a procedure that only Judges use to stop dangerous people from re-entering society until trial.', '2023-07-30 05:10:55'),
(21, 'P.C. 122', 'Speed Limits', '50 mph in a city and town, 100 mph on a divided highway/interstate', '2023-07-30 05:10:55'),
(22, 'P.C. 123', 'General Intent Crime', 'Offenses where prosecution has to show a person committed a criminal act. No concern whether the accused intended to produce the specific result of that act.', '2023-07-30 05:10:55'),
(23, 'P.C. 124', 'Specific Intent Crime', 'Offenses where prosecution has to show a person intended to commit an unlawful act, and specifically intended to violate the law.', '2023-07-30 05:10:55'),
(24, 'P.C. 125', 'PlayStation Pistols', 'VR weaponry are not under the weapon class system and are not illegal. It is advised you do not carry them on you in case they are mistaken for something else.', '2023-07-30 05:10:55'),
(25, 'P.C. 126', 'Narcotics', 'Painkillers, Antibiotics, Fentanyl or OxyContin (Oxy), including synthetic alternatives.', '2023-07-30 05:10:55'),
(26, 'P.C. 127', 'Lockpicks', '\"Lockpicks\" include Basic Lockpicks, Advanced Lockpicks, and Multitools.', '2023-09-03 09:33:00'),
(27, 'P.C 128', 'Firearms', 'Any weapon (including tasers and bean bag shot guns) which will or is designed to expel a projectile by the action of an explosion.', '2023-09-03 09:33:00'),
(28, 'P.C. 129', 'Distilled Spirits', 'Spirits produced through the process of distillation.', '2023-09-03 09:33:00'),
(29, 'P.C 115', 'Class 4 Weapon', 'Assault Rifles, Sniper Rifles, Muskets, including replicas. Full list of weaponry included is listed in the weaponry database.', '2025-03-25 20:38:00'),
(30, 'P.C 116', 'Class 5 Weapon', 'Incendiary, and/or explosive devices, including replicas. Full list of weaponry included is listed in the weaponry database.', '2025-03-25 20:38:00');

-- --------------------------------------------------------

--
-- Table structure for table `penal_code_enhancements`
--

CREATE TABLE `penal_code_enhancements` (
  `enhancement_id` int(11) NOT NULL,
  `label` varchar(50) DEFAULT NULL,
  `name` varchar(50) DEFAULT NULL,
  `abbreviation` varchar(50) DEFAULT NULL,
  `definition` longtext DEFAULT NULL,
  `multiplier` double DEFAULT NULL,
  `result` varchar(50) DEFAULT NULL,
  `added_date_time` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

--
-- Dumping data for table `penal_code_enhancements`
--

INSERT INTO `penal_code_enhancements` (`enhancement_id`, `label`, `name`, `abbreviation`, `definition`, `multiplier`, `result`, `added_date_time`) VALUES
(1, 'P.C. 1101', 'Accessory Before The Fact', 'ACC-BTF', 'Any person not present when the crime itself is committed, but has knowledge of the crime before or after the fact, and may assist in its commission.', 0.25, 'Seize', '2023-07-30 05:41:04'),
(2, 'P.C. 1102', 'Accessory After The Fact', 'ACC-ATF', 'Any person who aids or abets someone who has committed a crime after the crime has been committed with the intent to help the person avoid arrest or punishment.', 0.75, 'Seize', '2023-07-30 05:41:04'),
(3, 'P.C. 1103', 'Aiding and Abetting', 'AAA', 'Any person who aids in the active commission of a crime shall be given the same punishment', 1, 'Seize', '2023-07-30 05:41:04'),
(4, 'P.C. 1104', 'Applicability', 'APP', 'Charges labelled with Per as defined in TITLE 1. can be stacked, taking care to only add additional times and fines if it states PER next to the time and fines.', 1, 'Seize', '2023-07-30 05:41:04'),
(5, 'P.C. 1105', 'Attempt', 'ATT', 'A person who attempts to commit any crime but fails, is prevented, or is intercepted, shall be given the same punishment as if the offense was commited.', 1, 'Seize', '2023-07-30 05:41:04'),
(6, 'P.C. 1106', 'Conspiracy', 'CON', 'A person who conspires to commit any crime shall be given the same punishment as if the offense was commited.', 1, 'Seize', '2023-07-30 05:41:04'),
(7, 'P.C. 1107', 'Soliciting', 'SOL', 'A person who solicits for the commission or perpetration of any crime shall be given a similar punishments as if the offense was committed.', 0.5, 'Seize', '2023-07-30 05:41:04'),
(8, 'P.C. 1108', 'Gang Enhancement', 'GE', 'Any criminal activity with 2 or more known gang members involved shall be given a harsher total time and fine to deter future offences.', 1.5, '-', '2023-07-30 05:41:04'),
(9, 'P.C. 1109', 'Protected Persons', 'PP', 'Any criminal activity targeted at a public servant or peace officer shall be given a harsher total time and fine to deter future offences.', 1.4, '-', '2023-07-30 05:41:04'),
(10, 'PC. 1110', 'Public Menace', 'PM', 'Any person convicted of a serious felony who previously has been convicted of a serious felony is subject to an increase on their sentence per count of prior serious felony. (Manually add 600 months)', 1, '+600 Months Per', '2023-07-30 05:41:04'),
(11, 'P.C. 1111', 'Intent to Sell', 'ITS', 'A person who shows clear intent to sell; drugs, contraband or weaponry shall be given a harsher total time and fine to deter future offences.', 1.5, NULL, NULL),
(12, 'P.C. 1112', 'Protected Property', 'P-Prop', 'Any criminal activity targeted at a public servant\'s or peace officer\'s property or governement property shall be given a harsher total time and fine to deter future offences.', 1.2, NULL, NULL);

-- --------------------------------------------------------

--
-- Table structure for table `penal_code_titles`
--

CREATE TABLE `penal_code_titles` (
  `title_id` int(11) DEFAULT NULL,
  `name` varchar(50) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

--
-- Dumping data for table `penal_code_titles`
--

INSERT INTO `penal_code_titles` (`title_id`, `name`) VALUES
(1, 'Definitions'),
(2, 'Crimes Against the Person'),
(3, 'Crimes Against Property and Criminal Profiteering'),
(4, 'Crimes Against Public Decency'),
(5, 'Crimes Against Public Justice'),
(6, 'Crimes Against Public Peace'),
(7, 'Crimes Against Public Health and Safety'),
(8, 'Vehicular Offences'),
(9, 'Control of Deadly Weapons and Equipment'),
(10, 'State Code Violations'),
(11, 'Enhancements');

-- --------------------------------------------------------

--
-- Table structure for table `ranks`
--

CREATE TABLE `ranks` (
  `rank_order` int(11) NOT NULL,
  `rank_name` varchar(50) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

--
-- Dumping data for table `ranks`
--

INSERT INTO `ranks` (`rank_order`, `rank_name`) VALUES
(0, 'Chief'),
(1, 'Assistant Chief'),
(2, 'Deputy Chief'),
(3, 'Commander'),
(4, 'Captain'),
(5, 'Lieutenant'),
(6, 'Sergeant'),
(7, 'Corporal'),
(8, 'Senior Officer'),
(9, 'Officer'),
(10, 'Probationary Officer'),
(11, 'Cadet');

-- --------------------------------------------------------

--
-- Table structure for table `ranks_bcso`
--

CREATE TABLE `ranks_bcso` (
  `rank_order` int(11) DEFAULT NULL,
  `rank` varchar(50) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

--
-- Dumping data for table `ranks_bcso`
--

INSERT INTO `ranks_bcso` (`rank_order`, `rank`) VALUES
(0, 'Sheriff'),
(1, 'Undersheriff'),
(2, 'Assistant Sheriff'),
(3, 'Senior Executive Staff'),
(4, 'Executive Staff'),
(5, 'Deputy'),
(6, 'Honorary Deputy');

-- --------------------------------------------------------

--
-- Table structure for table `ranks_fib`
--

CREATE TABLE `ranks_fib` (
  `rank_order` int(11) DEFAULT NULL,
  `rank` varchar(50) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

--
-- Dumping data for table `ranks_fib`
--

INSERT INTO `ranks_fib` (`rank_order`, `rank`) VALUES
(0, 'Overwatch'),
(1, 'Director'),
(2, 'Deputy Director'),
(3, 'Executive Agent'),
(4, 'Special Agent'),
(5, 'Senior Agent'),
(6, 'Agent'),
(7, 'Trainee');

-- --------------------------------------------------------

--
-- Table structure for table `ranks_ftp`
--

CREATE TABLE `ranks_ftp` (
  `rank_order` int(11) DEFAULT NULL,
  `rank` varchar(50) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

--
-- Dumping data for table `ranks_ftp`
--

INSERT INTO `ranks_ftp` (`rank_order`, `rank`) VALUES
(0, 'Command'),
(1, 'Supervisor'),
(3, 'Trainer'),
(4, 'Junior Trainer'),
(2, 'Senior Trainer');

-- --------------------------------------------------------

--
-- Table structure for table `ranks_gw`
--

CREATE TABLE `ranks_gw` (
  `rank_order` int(11) DEFAULT NULL,
  `rank` varchar(50) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

--
-- Dumping data for table `ranks_gw`
--

INSERT INTO `ranks_gw` (`rank_order`, `rank`) VALUES
(0, 'Head Game Warden'),
(1, 'Senior Game Warden'),
(2, 'Assistant Game Warden'),
(3, 'Game Warden Supervisor'),
(4, 'Game Warden Deputy'),
(5, 'Game Warden Recruit');

-- --------------------------------------------------------

--
-- Table structure for table `ranks_ia`
--

CREATE TABLE `ranks_ia` (
  `rank_order` int(11) DEFAULT NULL,
  `rank` varchar(50) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

--
-- Dumping data for table `ranks_ia`
--

INSERT INTO `ranks_ia` (`rank_order`, `rank`) VALUES
(0, 'Commanding Officer'),
(1, 'Executive Officer'),
(2, 'Senior Agent'),
(5, 'Consultant'),
(4, 'Agent'),
(3, 'Senior Consultant'),
(6, 'Trainee');

-- --------------------------------------------------------

--
-- Table structure for table `ranks_management`
--

CREATE TABLE `ranks_management` (
  `rank_order` int(11) DEFAULT NULL,
  `rank` varchar(50) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

--
-- Dumping data for table `ranks_management`
--

INSERT INTO `ranks_management` (`rank_order`, `rank`) VALUES
(0, 'Command'),
(1, 'Member'),
(2, 'Provisional');

-- --------------------------------------------------------

--
-- Table structure for table `ranks_sahp`
--

CREATE TABLE `ranks_sahp` (
  `rank_order` int(11) DEFAULT NULL,
  `rank` varchar(50) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

--
-- Dumping data for table `ranks_sahp`
--

INSERT INTO `ranks_sahp` (`rank_order`, `rank`) VALUES
(0, 'Commisioner'),
(1, 'Colonel'),
(2, 'Major'),
(3, 'Executive Trooper'),
(4, 'Staff Trooper'),
(5, 'State Trooper');

-- --------------------------------------------------------

--
-- Table structure for table `ranks_swat`
--

CREATE TABLE `ranks_swat` (
  `rank_order` int(11) DEFAULT NULL,
  `rank` varchar(50) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

--
-- Dumping data for table `ranks_swat`
--

INSERT INTO `ranks_swat` (`rank_order`, `rank`) VALUES
(0, 'Command'),
(1, 'Operator - Alpha'),
(1, 'Operator - Bravo'),
(1, 'Breacher - Alpha'),
(1, 'Breacher - Bravo'),
(2, 'Recruit');

-- --------------------------------------------------------

--
-- Table structure for table `roster`
--

CREATE TABLE `roster` (
  `character_id` int(11) NOT NULL,
  `callsign` varchar(50) DEFAULT NULL,
  `discord_id` varchar(100) NOT NULL DEFAULT '',
  `rank` varchar(100) NOT NULL DEFAULT '',
  `status` varchar(100) NOT NULL DEFAULT '',
  `timezone` varchar(10) NOT NULL DEFAULT '',
  `last_promotion_date` datetime DEFAULT NULL,
  `joined_date` datetime NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `roster_bcso`
--

CREATE TABLE `roster_bcso` (
  `character_id` int(11) NOT NULL,
  `rank` varchar(50) DEFAULT NULL,
  `note` varchar(100) DEFAULT NULL,
  `joined_date` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `roster_certs`
--

CREATE TABLE `roster_certs` (
  `cert_id` int(11) NOT NULL,
  `character_id` int(11) NOT NULL DEFAULT 0,
  `type` varchar(50) NOT NULL DEFAULT '0',
  `notes` longtext NOT NULL,
  `added_date_time` datetime NOT NULL DEFAULT '0000-00-00 00:00:00'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `roster_changes`
--

CREATE TABLE `roster_changes` (
  `roster_change_id` int(11) NOT NULL,
  `changed_officer` int(11) NOT NULL DEFAULT 0,
  `changed_type` varchar(50) DEFAULT NULL,
  `changed_text` longtext NOT NULL,
  `changed_by` int(11) NOT NULL DEFAULT 0,
  `changed_date_time` datetime NOT NULL DEFAULT '0000-00-00 00:00:00'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `roster_doj`
--

CREATE TABLE `roster_doj` (
  `character_id` int(11) NOT NULL,
  `discord_id` varchar(100) NOT NULL DEFAULT '',
  `rank` varchar(50) NOT NULL DEFAULT '',
  `joined_date` datetime NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `roster_fib`
--

CREATE TABLE `roster_fib` (
  `character_id` int(11) NOT NULL,
  `rank` varchar(50) NOT NULL DEFAULT '',
  `note` varchar(100) DEFAULT '',
  `joined_date` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `roster_ftp`
--

CREATE TABLE `roster_ftp` (
  `character_id` int(11) NOT NULL,
  `rank` varchar(50) DEFAULT '',
  `note` varchar(100) DEFAULT '',
  `joined_date` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `roster_gw`
--

CREATE TABLE `roster_gw` (
  `character_id` int(11) NOT NULL,
  `rank` varchar(50) DEFAULT '',
  `note` varchar(100) DEFAULT '',
  `joined_date` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `roster_ia`
--

CREATE TABLE `roster_ia` (
  `character_id` int(11) NOT NULL,
  `rank` varchar(50) DEFAULT '',
  `note` varchar(100) DEFAULT '',
  `joined_date` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `roster_management`
--

CREATE TABLE `roster_management` (
  `character_id` int(11) NOT NULL,
  `rank` varchar(50) DEFAULT '',
  `note` varchar(100) DEFAULT '',
  `joined_date` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `roster_notes`
--

CREATE TABLE `roster_notes` (
  `note_id` int(11) NOT NULL,
  `character_id` int(11) NOT NULL DEFAULT 0,
  `type` varchar(50) NOT NULL,
  `note` longtext NOT NULL,
  `added_by` int(11) NOT NULL DEFAULT 0,
  `added_date_time` datetime NOT NULL DEFAULT '0000-00-00 00:00:00'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `roster_sahp`
--

CREATE TABLE `roster_sahp` (
  `character_id` int(11) NOT NULL,
  `rank` varchar(50) DEFAULT '',
  `note` varchar(100) DEFAULT '',
  `joined_date` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `roster_strikes`
--

CREATE TABLE `roster_strikes` (
  `strike_id` int(11) NOT NULL,
  `character_id` int(11) NOT NULL DEFAULT 0,
  `type` varchar(50) NOT NULL DEFAULT '0',
  `reason` longtext NOT NULL,
  `authorized_by` int(11) NOT NULL DEFAULT 0,
  `added_by` int(11) NOT NULL DEFAULT 0,
  `added_date_time` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `roster_swat`
--

CREATE TABLE `roster_swat` (
  `character_id` int(11) NOT NULL,
  `rank` varchar(50) DEFAULT '',
  `note` varchar(100) DEFAULT '',
  `joined_date` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `sessions`
--

CREATE TABLE `sessions` (
  `id` int(11) NOT NULL,
  `user_id` int(11) NOT NULL DEFAULT 0,
  `access_token` longtext NOT NULL,
  `refresh_token` longtext NOT NULL,
  `is_revoked` tinyint(1) DEFAULT 0,
  `expires_at` timestamp NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `tags`
--

CREATE TABLE `tags` (
  `tag_id` int(11) DEFAULT NULL,
  `tag_value` int(11) DEFAULT NULL,
  `tag_color` varchar(50) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `time`
--

CREATE TABLE `time` (
  `character_id` int(11) NOT NULL,
  `on_duty_time` longtext DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;

--
-- Triggers `time`
--
DELIMITER $$
CREATE TRIGGER `before_insert_time` BEFORE INSERT ON `time` FOR EACH ROW BEGIN
    IF NEW.on_duty_time IS NULL THEN
        SET NEW.on_duty_time = '{}';
    END IF;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `before_update_time` BEFORE UPDATE ON `time` FOR EACH ROW BEGIN
    IF NEW.on_duty_time IS NULL THEN
        SET NEW.on_duty_time = '{}';
    END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `time_extra`
--

CREATE TABLE `time_extra` (
  `time_id` int(11) NOT NULL,
  `character_id` int(11) NOT NULL DEFAULT 0,
  `reasoning` longtext NOT NULL,
  `extra_time` int(11) NOT NULL DEFAULT 0,
  `week_number` int(11) NOT NULL DEFAULT 0,
  `added_by` int(11) NOT NULL DEFAULT 0,
  `added_date_time` datetime NOT NULL DEFAULT '0000-00-00 00:00:00'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `vehicles`
--

CREATE TABLE `vehicles` (
  `model_name` varchar(50) NOT NULL DEFAULT 'vehicle',
  `label` varchar(50) DEFAULT NULL,
  `id` varchar(50) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

--
-- Dumping data for table `vehicles`
--

INSERT INTO `vehicles` (`model_name`, `label`, `id`) VALUES
('06srt', '2006 Demon Chaser', '-1123464718'),
('1200rta', 'Bavaria 1200RT', '258787652'),
('1500dj', 'Chefboyardee 1500DJ', '-1471265912'),
('16charger', '16 Charge Dodge', '-1513691047'),
('16exp_ems', 'Falcon Pathfinder', '-525474865'),
('17mansorypnmr', '2017 Porchse Mansory Panamera', '-77591427'),
('180sx', 'Nihon 180sx', '-1467569396'),
('18performante', 'Rambarini Performante', '836213613'),
('2013rs7', 'Orion RS7', '-303990162'),
('2020silv', 'Silverline Trail Boss', '-1999472724'),
('20ramrbc', 'Dog Ram Towtruck', '1328214065'),
('21tr14charg', '2014 Charge Dodger', '-982599050'),
('21tr16fpiu', '2016 Falcon Pathfinder FPIU', '-1327443726'),
('21trcvpi', '2013 Falcon Crown Vicar CVPI', '1731890143'),
('21trfpis', '2018 Falcon Tauron FPIS', '-915439516'),
('24brz', '2024 Subsonic XRZ', '1129263476'),
('24rs7', '2024 Orion 7-RS', '-659369999'),
('24tac', '2024 Typhoon Traveler', '-759439799'),
('4881', 'Ferari 488', '-749347224'),
('488lb', '2018 Ferari 488 GTB', '-1380779501'),
('4c', '2018 Alpha Romea 4C Spider', '-1339710539'),
('500gtrlam', 'Rambarini Diablo', '1920158251'),
('66fast', '66 Flamestride Galloper', '1341323324'),
('66nov', '1966 Revvy Nebula', '1215871760'),
('675ltsp', '2016 McLoren 675LT Freedom Stroll', '-304327697'),
('69charger', '69 Charge RT10', '981770764'),
('74civicrs', '1974 Harmonia Civick', '-359149316'),
('765lt', 'Mercia McLarson 765', '-984243759'),
('911r', 'Porchse 911R', '144259586'),
('911rsr', '2023 Primordial GTS-63', '1904330251'),
('918', '2015 Porchse 918 Spider', '-2091594350'),
('93mustang', '1993 Foxfire Serpant', '1609525731'),
('992ts', '2021 Pork 911 992 Turbo S', '-1558980261'),
('99viper', '99 Venom Charger', '726460559'),
('a10c', 'A-10C Lightning II', '153036344'),
('a321', 'Skybus A321', '1083058878'),
('a6', '2020 Orion A6', '-494839908'),
('a70', '1990 Typhoon Sura Mk3', '955107855'),
('adder', 'Adder', '-1216765807'),
('afo', 'Air Force One', '-1139558211'),
('airbus', 'Airport Bus', '1283517198'),
('airtug', 'Airtug', '1560980623'),
('akula', 'Akula', '1181327175'),
('akuma', 'Akuma', '1672195559'),
('aleutian', 'Aleutian', '-38879449'),
('alkonost', 'RO-86 Alkonost', '-365873403'),
('alpha', 'Alpha', '767087018'),
('alphaz1', 'Alpha-Z1', '-1523619738'),
('ambulance', 'Ambulance', '1171614426'),
('ambulance6', 'F-450 Ambulance', '-583006956'),
('amels200', 'Ameliorate 200', '-861217386'),
('amggtbyv', 'OMG GT LegacyRP Edition', '-2051005413'),
('amggtr', '2016 Mercia-Benz AMG GT', '-915188472'),
('amv23', 'Eston Maltin Vantage', '-946960713'),
('annihilator', 'Annihilator', '837858166'),
('annihilator2', 'Annihilator Stealth', '295054921'),
('apc', 'APC', '562680400'),
('arbitergt', 'Arbiter GT', '1549009676'),
('ardent', 'Ardent', '159274291'),
('armytanker', 'Army Trailer', '-1207431159'),
('armytrailer', 'Army Trailer', '-1476447243'),
('armytrailer2', 'Army Trailer', '-1637149482'),
('arrowladder', 'Ladder Firetruck', '-1762329869'),
('as332', 'Eurocopter AS332 EMS Airbus', '1290625056'),
('as350', 'AS-350 Helicopter', '1346171487'),
('asbo', 'Asbo', '1118611807'),
('asea', 'Asea', '-1809822327'),
('asea2', 'Asea', '-1807623979'),
('ast', 'Stellar Orion Conqueror', '-1865955898'),
('asterope', 'Asterope', '-1903012613'),
('asterope2', 'Asterope GZ', '-741120335'),
('astron', 'Astron', '629969764'),
('astron2', 'Astron Custom', '-1491268273'),
('atst', 'AT-ST Walker', '1287608798'),
('autarch', 'Autarch', '-313185164'),
('avarus', 'Avarus', '-2115793025'),
('avenger', 'Avenger', '-2118308144'),
('avenger2', 'Avenger', '408970549'),
('avenger3', 'Avenger', '-426933872'),
('avenger4', 'Avenger', '-69293006'),
('aventador', '2019 Rambarini Aventador S', '1890188937'),
('avisa', 'Avisa', '-1706603682'),
('b17e', 'B-17E Soaring Fortress', '-1635068488'),
('b52', 'B-52H Stratofortress', '-1528416545'),
('b737800', 'Boinger 737-800', '-1504665178'),
('bagger', 'Bagger', '-2140431165'),
('baletrailer', 'Baletrailer', '-399841706'),
('baller', 'Baller', '-808831384'),
('baller2', 'Baller', '142944341'),
('baller3', 'Baller LE', '1878062887'),
('baller4', 'Baller LE LWB', '634118882'),
('baller5', 'Baller LE (Armored)', '470404958'),
('baller6', 'Baller LE LWB (Armored)', '666166960'),
('baller7', 'Baller ST', '359875117'),
('baller8', 'Baller ST-D', '-863358884'),
('banshee', 'Banshee', '-1041692462'),
('banshee2', 'Banshee 900R', '633712403'),
('banshee3', 'Banshee GTS', '-660007725'),
('barracks', 'Barracks', '-823509173'),
('barracks2', 'Barracks Semi', '1074326203'),
('barracks3', 'Barracks', '630371791'),
('barrage', 'Barrage', '-212993243'),
('bati', 'Bati 801', '-114291515'),
('bati2', 'Bati 801RR', '-891462355'),
('bc', 'Pamami Huayaya BC Roadster', '-402398867'),
('benson', 'Benson', '2053223216'),
('benson2', 'Benson (Cluckin\' Bell)', '728350375'),
('bentaygast', '2017 Bentleigh Bentiga', '-1980604310'),
('benzsl63', '2002 Midnight Breeze S63', '-2025387310'),
('berlinetta', 'Ferari Berlinetta', '1106185298'),
('besra', 'Besra', '1824333165'),
('bestiagts', 'Bestia GTS', '1274868363'),
('bf400', 'BF400', '86520421'),
('bfinjection', 'Injection', '1126868326'),
('biff', 'Biff', '850991848'),
('bifta', 'Bifta', '-349601129'),
('bison', 'Bison', '-16948145'),
('bison2', 'Bison', '2072156101'),
('bison3', 'Bison', '1739845664'),
('bjxl', 'BeeJay XL', '850565707'),
('blackwing', '2022 Zaddy Batwing', '1379910105'),
('blade', 'Blade', '-1205801634'),
('blazer', 'Blazer', '-2128233223'),
('blazer2', 'Blazer Lifeguard', '-48031959'),
('blazer3', 'Hot Rod Blazer', '-1269889662'),
('blazer4', 'Street Blazer', '-440768424'),
('blazer5', 'Blazer Aqua', '-1590337689'),
('blimp', 'Atomic Blimp', '-150975354'),
('blimp2', 'Xero Blimp', '-613725916'),
('blimp3', 'Blimp', '-307958377'),
('blista', 'Blista', '-344943009'),
('blista2', 'Blista Compact', '1039032026'),
('blista3', 'Go Go Monkey Blista', '-591651781'),
('bmci', 'Bavaria M5', '1093697054'),
('bmwg07', 'Bavaria G 07', '497572160'),
('bmx', 'BMX', '1131912276'),
('boattrailer', 'Boat Trailer', '524108981'),
('boattrailer2', 'Boat Trailer', '1835260592'),
('boattrailer3', 'Boat Trailer', '1539159908'),
('bobcatxl', 'Bobcat XL', '1069929536'),
('bodhi2', 'Bodhi', '-1435919434'),
('bombushka', 'RM-10 Bombushka', '-32878452'),
('boor', 'Boor', '996383885'),
('boxville', 'Boxville', '-1987130134'),
('boxville2', 'Boxville', '-233098306'),
('boxville3', 'Boxville', '121658888'),
('boxville4', 'Boxville', '444171386'),
('boxville5', 'Armored Boxville', '682434785'),
('boxville6', 'Boxville (LSDS)', '-842765535'),
('brawler', 'Brawler', '-1479664699'),
('brickade', 'Brickade', '-305727417'),
('brickade2', 'Brickade 6x6', '-1576586413'),
('brigham', 'Brigham', '-654498607'),
('brioso', 'Brioso R/A', '1549126457'),
('brioso2', 'Brioso 300', '1429622905'),
('brioso3', 'Brioso 300 Widebody', '15214558'),
('broadway', 'Broadway', '-1933242328'),
('bruiser', 'Apocalypse Bruiser', '668439077'),
('bruiser2', 'Future Shock Bruiser', '-1694081890'),
('bruiser3', 'Nightmare Bruiser', '-2042350822'),
('brushram', 'Brush Ram Firetruck', '-718863280'),
('brutus', 'Apocalypse Brutus', '2139203625'),
('brutus2', 'Future Shock Brutus', '-1890996696'),
('brutus3', 'Nightmare Brutus', '2038858402'),
('brz13', '2013 Subari BRZ', '1411828323'),
('bsvan', 'Burger Shot Van', '-101479964'),
('btype', 'Roosevelt', '117401876'),
('btype2', 'Fränken Stange', '-831834716'),
('btype3', 'Roosevelt Valor', '-602287871'),
('buccaneer', 'Buccaneer', '-682211828'),
('buccaneer2', 'Buccaneer Custom', '-1013450936'),
('buffalo', 'Buffalo', '-304802106'),
('buffalo2', 'Buffalo S', '736902334'),
('buffalo3', 'Sprunk Buffalo', '237764926'),
('buffalo4', 'Buffalo STX', '-619930876'),
('buffalo5', 'Buffalo EVX', '165968051'),
('bugatti', 'Bugarto Verona', '-1444047101'),
('bulldozer', 'Dozer', '1886712733'),
('bullet', 'Bullet', '-1696146015'),
('burrito', 'Burrito', '-1346687836'),
('burrito2', 'Bugstars Burrito', '-907477130'),
('burrito3', 'Burrito', '-1743316013'),
('burrito4', 'Burrito', '893081117'),
('burrito5', 'Burrito', '1132262048'),
('bus', 'Bus', '-713569950'),
('buzzard', 'Buzzard Attack Chopper', '788747387'),
('buzzard2', 'Buzzard', '745926877'),
('buzzard4', 'Police Pontoon Helicopter', '686516684'),
('buzzard5', 'Police MH6 Little Bird', '1925283191'),
('buzzard6', 'EMS Pontoon Rescue Helicopter', '51060236'),
('c10', '1960 Thundersteel Roamer C ten', '71033349'),
('c63', '2006 Mercia-Benz AMG C63', '-1215316954'),
('c63s', 'Mercia-Benz C63s', '2099088182'),
('c7', 'Corvex C7', '874739883'),
('c7r', 'RMOD Corvex C7', '-661719484'),
('c8p', 'Spyker C8', '601425127'),
('cablecar', 'Cable Car', '-960289747'),
('caddy', 'Caddy', '1147287684'),
('caddy2', 'Caddy', '-537896628'),
('caddy3', 'Caddy', '-769147461'),
('calico', 'Calico GTF', '-1193912403'),
('camaro_ss', 'Camero SS', '1053107333'),
('camaro70', '17 Camero', '-1201690969'),
('camarobb', 'Staff Car (THIS IS A JOKE)', '2030763030'),
('camper', 'Camper', '1876516712'),
('caracara', 'Caracara', '1254014755'),
('caracara2', 'Caracara 4x4', '-1349095620'),
('carbonizzare', 'Carbonizzare', '2072687711'),
('carbonrs', 'Carbon RS', '11251904'),
('cargobob', 'Cargobob', '-50547061'),
('cargobob2', 'Cargobob', '1621617168'),
('cargobob3', 'Cargobob', '1394036463'),
('cargobob4', 'Cargobob', '2025593404'),
('cargobob5', 'DH-7 Iron Mule', '-352682313'),
('cargoplane', 'Cargo Plane', '368211810'),
('cargoplane2', 'Cargo Plane', '-1958189855'),
('carlton', '1990 Unity Charlatan', '-2047200683'),
('casco', 'Casco', '941800958'),
('castigator', 'Castigator', '1307736079'),
('cavalcade', 'Cavalcade', '2006918058'),
('cavalcade2', 'Cavalcade', '-789894171'),
('cavalcade3', 'Cavalcade XL', '-1029730482'),
('cerberus', 'Apocalypse Cerberus', '-801550069'),
('cerberus2', 'Future Shock Cerberus', '679453769'),
('cerberus3', 'Nightmare Cerberus', '1909700336'),
('challenger18', '2018 Charge Challenger Hellcat', '-1572984573'),
('champion', 'Champion', '-915234475'),
('chavosv6', 'Chavos V6', '1992041063'),
('cheburek', 'Cheburek', '-988501280'),
('cheetah', 'Cheetah', '-1311154784'),
('cheetah2', 'Cheetah Classic', '223240013'),
('chernobog', 'Chernobog', '-692292317'),
('chevropremtn', 'Cheverlet Blazing Premium 2019', '28080420'),
('chimera', 'Chimera', '6774487'),
('chino', 'Chino', '349605904'),
('chino2', 'Chino Custom', '-1361687965'),
('cinquemila', 'Cinquemila', '-1527436269'),
('citationii', 'Cenna 550 Citation II', '-366628154'),
('cliffhanger', 'Cliffhanger', '390201602'),
('clique', 'Clique', '-1566607184'),
('clique2', 'Clique Wagon', '-979292575'),
('clkgtr', 'Mercedes-Benz CLK GTR 1998', '-1618909092'),
('club', 'BF Club', '-2098954619'),
('coach', 'Dashound', '-2072933068'),
('cog55', 'Cognoscenti 55', '906642318'),
('cog552', 'Cognoscenti 55 (Armored)', '704435172'),
('cogcabrio', 'Cognoscenti Cabrio', '330661258'),
('cognoscenti', 'Cognoscenti', '-2030171296'),
('cognoscenti2', 'Cognoscenti (Armored)', '-604842630'),
('comet2', 'Comet', '-1045541610'),
('comet3', 'Comet Retro Custom', '-2022483795'),
('comet4', 'Comet Safari', '1561920505'),
('comet5', 'Comet SR', '661493923'),
('comet6', 'Comet S2', '-1726022652'),
('comet7', 'Comet S2 Cabrio', '1141395928'),
('conada', 'Conada', '-477831899'),
('conada2', 'Weaponized Conada', '-1659004814'),
('contender', 'Contender', '683047626'),
('contss18c', '2018 Bentleigh Continent GT Cabrio', '-1013118944'),
('coquette', 'Coquette', '108773431'),
('coquette2', 'Coquette Classic', '1011753235'),
('coquette3', 'Coquette BlackFin', '784565758'),
('coquette4', 'Coquette D10', '-1728685474'),
('coquette5', 'Coquette D1', '-1958428933'),
('coquette6', 'Coquette D5', '127317925'),
('corsita', 'Corsita', '-754687673'),
('coureur', 'La Coureuse', '610429990'),
('cruiser', 'Cruiser', '448402357'),
('crusader', 'Crusader', '321739290'),
('cuban800', 'Cuban 800', '-644710429'),
('cutter', 'Cutter', '-1006919392'),
('cyclone', 'Cyclone', '1392481335'),
('cyclone2', 'Cyclone II', '386089410'),
('cypher', 'Cypher', '1755697647'),
('daemon', 'Daemon', '2006142190'),
('daemon2', 'Daemon Custom', '-1404136503'),
('db11', 'Stellar Orion DB11', '765170133'),
('dc5', '2003 Harmonia Integra Type R', '-2138685623'),
('dcd', 'Challenger Daemon', '-1011366497'),
('deathbike', 'Apocalypse Deathbike', '-27326686'),
('deathbike2', 'Future Shock Deathbike', '-1812949672'),
('deathbike3', 'Nightmare Deathbike', '-1374500452'),
('deathstar', 'Death Star', '875388065'),
('deepspace', 'Deepspace 9 spaceship', '1396997160'),
('defiler', 'Defiler', '822018448'),
('deity', 'Deity', '1532171089'),
('deluxo', 'Deluxo', '1483171323'),
('deluxo2', 'Supreme Lux', '1080561763'),
('deveste', 'Deveste Eight', '1591739866'),
('deviant', 'Deviant', '1279262537'),
('diablous', 'Diabolus', '-239841468'),
('diablous2', 'Diabolus Custom', '1790834270'),
('dilettante', 'Dilettante', '-1130810103'),
('dilettante2', 'Dilettante', '1682114128'),
('dinghy', 'Dinghy', '1033245328'),
('dinghy2', 'Dinghy', '276773164'),
('dinghy3', 'Dinghy', '509498602'),
('dinghy4', 'Dinghy', '867467158'),
('dinghy5', 'Weaponized Dinghy', '-980573366'),
('dloader', 'Duneloader', '1770332643'),
('dmc12wb', '1981 TDM Flux', '-1640135981'),
('do228', 'Dorner 228', '-1578888621'),
('docktrailer', 'Docktrailer', '-2140210194'),
('docktug', 'Docktug', '-884690486'),
('dodo', 'Dodo', '-901163259'),
('dogmaf12', 'Pinarello Doctrine F12', '-256227963'),
('dominator', 'Dominator', '80636076'),
('dominator10', 'Dominator FX', '1579902654'),
('dominator2', 'Pisswasser Dominator', '-915704871'),
('dominator3', 'Dominator GTX', '-986944621'),
('dominator4', 'Apocalypse Dominator', '-688189648'),
('dominator5', 'Future Shock Dominator', '-1375060657'),
('dominator6', 'Nightmare Dominator', '-1293924613'),
('dominator7', 'Dominator ASP', '426742808'),
('dominator8', 'Dominator GTT', '736672010'),
('dominator9', 'Dominator GT', '-441209695'),
('dorado', 'Dorado', '-768044142'),
('double', 'Double-T', '-1670998136'),
('drafter', '8F Drafter', '686471183'),
('dragoon', '2008 Dragon Hog', '1576693251'),
('draugur', 'Draugur', '-768236378'),
('driftcheburek', 'Cheburek', '-1466692365'),
('driftcypher', 'Cypher', '258105345'),
('drifteuros', 'Euros', '821121576'),
('driftfr36', 'FR36', '-1479935577'),
('driftfuto', 'Futo GTX', '-181562642'),
('driftfuto2', 'Futo', '-1289225626'),
('driftjester', 'Jester RR', '-1763273939'),
('driftjester3', 'Jester Classic', '-362690998'),
('driftnebula', 'Nebula Turbo', '1690421418'),
('driftremus', 'Remus', '-1624083468'),
('driftsentinel', 'Sentinel Classic Widebody', '-986656474'),
('drifttampa', 'Drift Tampa', '-1696319096'),
('driftvorschlag', 'Vorschlaghammer', '-143587026'),
('driftyosemite', 'Drift Yosemite', '-1681653521'),
('driftzr350', 'ZR350', '1923534526'),
('dubsta', 'Dubsta', '1177543287'),
('dubsta2', 'Dubsta', '-394074634'),
('dubsta3', 'Dubsta 6x6', '-1237253773'),
('dukes', 'Dukes', '723973206'),
('dukes2', 'Duke O\'Death', '-326143852'),
('dukes3', 'Beater Dukes', '2134119907'),
('dump', 'Dump', '-2130482718'),
('dune', 'Dune Buggy', '-1661854193'),
('dune2', 'Space Docker', '534258863'),
('dune3', 'Dune FAV', '1897744184'),
('dune4', 'Ramp Buggy', '-827162039'),
('dune5', 'Ramp Buggy', '-312295511'),
('duster', 'Duster', '970356638'),
('duster2', 'Duster 300-H', '84351789'),
('dynasty', 'Dynasty', '310284501'),
('dyne', '2004 Harleyway Dyna Super Glide', '-1895423907'),
('e46', '2001 Bavaria M3 E46', '1840495621'),
('e89', '2010 Bavaria Z4 GT3', '992657080'),
('eclipse', 'Mistral Eclipse', '1603211447'),
('eg6', 'Harmonia Civic EG', '-1940854501'),
('elegy', 'Elegy Retro Custom', '196747873'),
('elegy2', 'Elegy RH8', '-566387422'),
('ellie', 'Ellie', '-1267543371'),
('ellie6str', 'Ellie 6GT Drift', '366786352'),
('emerus', 'Emerus', '1323778901'),
('emperor', 'Emperor', '-685276541'),
('emperor2', 'Emperor', '-1883002148'),
('emperor3', 'Emperor', '-1241712818'),
('enduro', 'Enduro', '1753414259'),
('entity2', 'Entity XXR', '-2120700196'),
('entity3', 'Entity MT', '1748565021'),
('entityxf', 'Entity XF', '-1291952903'),
('envisage', 'Envisage', '1121330119'),
('er34', '1999 Nihon Skyline ER34 GTT', '1328869613'),
('esskey', 'Esskey', '2035069708'),
('eudora', 'Eudora', '-1249788006'),
('euros', 'Euros', '2038480341'),
('eurosx32', 'Euros X32', '-999594302'),
('everon', 'Everon', '-1756021720'),
('everon2', 'Hotring Everon', '-131348178'),
('evo2', '2021 Ramberini Evo 2', '1794105431'),
('evo9', 'Mistral Evolution', '-228528329'),
('evoque', 'Range Rambler Evoque', '1663453404'),
('exemplar', 'Exemplar', '-5153954'),
('f111a', 'F-111A Anteater', '-830514257'),
('f117a', 'F-117A Nighthawk', '506038926'),
('f14a2', 'F-14A Alleycat', '-848721350'),
('f150', 'F1 Fifty', '-1304790695'),
('f15078', '78 Ford F1 Fifty', '77525437'),
('f15j2', 'F-15J Eagle', '2025009910'),
('f16c', 'F-16C Combat Falcon', '-2051171080'),
('f22a', 'F-22 Predator', '2061630439'),
('f35a', 'F-35A Lightning', '-804181225'),
('f430s', '2004 Flamestrike XF-430 Serpent', '-1567297735'),
('f620', 'F620', '-591610296'),
('f82lw', '2018 Bavaria M4 Freedom Stroll', '1441487375'),
('fa18e', 'F18E Super Hornet', '-1598193226'),
('faction', 'Faction', '-2119578145'),
('faction2', 'Faction Custom 1', '-1790546981'),
('faction3', 'Faction Custom Donk', '-2039755226'),
('fagaloa', 'Fagaloa', '1617472902'),
('faggio', 'Faggio Sport', '-1842748181'),
('faggio2', 'Faggio', '55628203'),
('faggio3', 'Faggio Mod', '-1289178744'),
('falcon', 'Millennium Falcon', '-1065246059'),
('fallen', 'Fallen Rider', '1713614119'),
('fbi', 'FIB', '1127131465'),
('fbi2', 'FIB', '-1647941228'),
('fc3s', '1990 Madza RX7', '3467202'),
('fcr', 'FCR 1000', '627535535'),
('fcr2', 'FCR 1000 Custom', '-757735410'),
('fd', 'Madza FD', '-1589129298'),
('felon', 'Felon', '-391594584'),
('felon2', 'Felon GT', '-89291282'),
('feltzer2', 'Feltzer', '-1995326987'),
('feltzer3', 'Feltzer Classic', '-1566741232'),
('fgt', '2005 Falcon GT', '1315816827'),
('fibb', 'Unmarked Baller', '228428425'),
('fibb2', 'Unmarked Buffalo', '-426439627'),
('fibc3', 'Unmarked Contendor', '1346471864'),
('fibd3', 'Unmarked Dominator', '793004262'),
('fibh', 'Unmarked Huntley', '1255834894'),
('fibk2', 'Unmarked Kurama', '2018131173'),
('fibs', 'Unmarked Speedo', '-1360147149'),
('filthynsx', 'Unclean NSAX', '-2096912321'),
('firebird77', '77 Phoenix', '2041888639'),
('firebolt', 'Firebolt ASP', '-973016778'),
('firetruk', 'Fire Truck', '1938952078'),
('fixter', 'Fixter', '-836512833'),
('fk8', '2018 Harmonia Civic Type-R', '-1745789659'),
('flashgt', 'Flash GT', '-1259134696'),
('flatbed', 'Flatbed', '1353720154'),
('flhxs_streetglide_special18', 'Harleyway Streetglide Special', '196279228'),
('fmj', 'FMJ', '1426219628'),
('focusrs', 'Falcon Focus RS 2017', '819937652'),
('foodbike', 'Food Delivery Scooter', '1236861718'),
('foodbike2', 'Food Delivery Scooter v2', '-1184640984'),
('foodcar2', 'Food Delivery Blista', '-1662714101'),
('foodcar3', 'Food Delivery Karin', '1806048398'),
('foodcar4', 'Pizza Delivery Panto', '946779680'),
('foodcar5', 'Food Delivery Emperor', '-2027301995'),
('foodcar6', 'Up&Atom Food Delivery', '1142902145'),
('foodcar7', 'Rice&Fins Food Delivery', '1374480668'),
('forgt50020', 'Falcon Stallion Shelby', '-1532987787'),
('forklift', 'Forklift', '1491375716'),
('formula', 'PR4', '340154634'),
('formula2', 'R88', '-1960756985'),
('foxc90', 'Beechking Sky Air', '-472912504'),
('foxch47', 'CH47 Cargobob (Military)', '-1222329808'),
('foxharley1', '1996 Harleyway Soft Trail', '545993358'),
('foxharley2', 'Harleyway CVO', '305501667'),
('fpump', 'Pump Firetruck', '435658079'),
('fq2', 'FQ 2', '-1137532101'),
('fr36', 'FR36', '-465825307'),
('freecrawler', 'Freecrawler', '-54332285'),
('freight', 'Freight Train', '1030400667'),
('freight2', 'Freight Train', '-442229240'),
('freightcar', 'Freight Train', '184361638'),
('freightcar2', 'Freight Train', '-1108591207'),
('freightcar3', 'Freight Train', '-1874009509'),
('freightcont1', 'Freight Train', '920453016'),
('freightcont2', 'Freight Train', '240201337'),
('freightgrain', 'Freight Train', '642617954'),
('freighttrailer', 'Freighttrailer', '-777275802'),
('frogger', 'Frogger', '744705981'),
('frogger2', 'Frogger', '1949211328'),
('fugitive', 'Fugitive', '1909141499'),
('furia', 'Furia', '960812448'),
('furoregt', 'Furore GT', '-1089039904'),
('fusilade', 'Fusilade', '499169875'),
('futo', 'Futo', '2016857647'),
('futo2', 'Futo GTX', '-1507230520'),
('g65', 'Mercia-Benz G65', '178350184'),
('gargoyle', 'Gargoyle', '741090084'),
('gauntlet', 'Gauntlet', '-1800170043'),
('gauntlet2', 'Redwood Gauntlet', '349315417'),
('gauntlet3', 'Gauntlet Classic', '722226637'),
('gauntlet4', 'Gauntlet Hellfire', '1934384720'),
('gauntlet5', 'Gauntlet Classic Custom', '-2122646867'),
('gauntlet6', 'Hotring Hellfire', '1336514315'),
('gauntlet6str', 'Goliath 6GT', '2074435700'),
('gb200', 'GB200', '1909189272'),
('gburrito', 'Gang Burrito', '-1745203402'),
('gburrito2', 'Gang Burrito', '296357396'),
('gclas9', 'G Carriage', '178657734'),
('gcptvan', 'Prisoner transporter', '-694377870'),
('gdaq50', '2024 Eterniti S50', '1582249670'),
('gemera', 'Koenigseggs Camera', '285057540'),
('giuliaqv', 'Alpha Romeo Juliet', '-760865351'),
('gladiator', '2023 Sheep Annihilator', '1256579920'),
('glendale', 'Glendale', '75131841'),
('glendale2', 'Glendale Custom', '-913589546'),
('globe', 'C-17A Globemaster III', '-677466500'),
('gm5303', 'GM TDH-5303', '922929947'),
('goldwing', 'Harmonia GL1800 Goldwing', '-1762326590'),
('golf4', '1998 MV Tennis GTI Mk4', '-575431438'),
('goon', '2022 Unistrike Goon', '457113946'),
('govburb', 'Governors Suburbia', '-2040709816'),
('gp1', 'GP1', '1234311532'),
('graintrailer', 'Graintrailer', '1019737494'),
('granger', 'Granger', '-1775728740'),
('granger2', 'Granger 3600LX', '-261346873'),
('granlb', 'Maseratti Freedom Stroll', '-1907071539'),
('greenwood', 'Greenwood', '40817712'),
('gresley', 'Gresley', '-1543762099'),
('growler', 'Growler', '1304459735'),
('gstsierra1', '2004 GMsea Guerra', '1151402103'),
('gstylingg35', '2008 Infinity G35', '-207978407'),
('gt430', '2023 Unity GT 430', '664407199'),
('gt500', 'GT500', '-2079788230'),
('gtrlb2', '2019 Nikon GT-R LB Performance', '252937954'),
('gtx', '1971 Plimoth GTX', '1481822982'),
('guardian', 'Guardian', '-2107990196'),
('gurkha', '2016 Terrafirm Gurkha RPV', '1636930844'),
('gxr33', '1993 Nihon (R33)', '-977717902'),
('habanero', 'Habanero', '884422927'),
('hakuchou', 'Hakuchou', '1265391242'),
('hakuchou2', 'Hakuchou Drag', '-255678177'),
('halftrack', 'Half-track', '-32236122'),
('handler', 'Dock Handler', '444583674'),
('harleychopper', 'Harleyway Chopper', '-282883309'),
('harleychopper2', 'Harleyway, Fat Boy', '-183220387'),
('hauler', 'Hauler', '1518533038'),
('hauler2', 'Hauler Custom', '387748548'),
('havok', 'Havok', '-1984275979'),
('hellephantdurango', 'Dodge Durango Hellephant 2022', '-212876261'),
('hellion', 'Hades Import', '-362150785'),
('hermes', 'Hermes', '15219735'),
('hexer', 'Hexer', '301427732'),
('hmmwv', 'M1025 HMMWV', '326911924'),
('honcrx91', '1990 Harmonia CRX Si-R', '487628275'),
('honcub', 'Honga 2&4 Project', '400528305'),
('hotknife', 'Hotknife', '37348240'),
('hotring', 'Hotring Sabre', '1115909093'),
('howard', 'Howard NX-25', '-1007528109'),
('hs748', 'Hawkley HS 748', '-1414960708'),
('hsvmaloo', 'HSV, Maloo', '1340847573'),
('huayrabc19', '2019 Pastrami Hyena', '-742080046'),
('humev22', '2023 Hammer EV', '-216635788'),
('hunter', 'FH-1 Hunter', '-42959138'),
('huntley', 'Huntley S', '486987393'),
('hustler', 'Hustler', '600450546'),
('hvrod', 'Harleyway Nightrod', '-1474280704'),
('hydra', 'Hydra', '970385471'),
('i422', '2022 Bavaria EV4', '1546483767'),
('i8', 'Bavaria i8', '1718441594'),
('ignus', 'Ignus', '-1444114309'),
('ignus2', 'Weaponized Ignus', '956849991'),
('ikx3dark24', 'Fork Mustard Dark Horse 2024', '1829661543'),
('ikx3gt3rs23', 'Pork 119 GT3 RS 2023', '1508632869'),
('ikx3levis', 'Jeeb CJ-5 Renegader Levi\'s Edition 1976', '-1557586207'),
('ikx3m2p23', 'BMV M2 M Performance 2023', '-1013967295'),
('imorgon', 'Imorgon', '-1132721664'),
('impaler', 'Impaler', '-2096690334'),
('impaler2', 'Apocalypse Impaler', '1009171724'),
('impaler3', 'Future Shock Impaler', '-1924800695'),
('impaler4', 'Nightmare Impaler', '-1744505657'),
('impaler5', 'Impaler SZ', '-478639183'),
('impaler6', 'Impaler LX', '-178442374'),
('imperator', 'Apocalypse Imperator', '444994115'),
('imperator2', 'Future Shock Imperator', '1637620610'),
('imperator3', 'Nightmare Imperator', '-755532233'),
('indiancdh', '2020 Indigenous Chief Dark Steed', '-1035938690'),
('inductor', 'Inductor', '-897824023'),
('inductor2', 'Junk Energy Inductor', '-1983622024'),
('infernus', 'Infernus', '418536135'),
('infernus2', 'Infernus Classic', '-1405937764'),
('ingot', 'Ingot', '-1289722222'),
('innovation', 'Innovation', '-159126838'),
('insurgent', 'Insurgent Pick-Up', '-1860900134'),
('insurgent2', 'Insurgent', '2071877360'),
('insurgent3', 'Insurgent Pick-Up Custom', '-1924433270'),
('intruder', 'Intruder', '886934177'),
('iowa', 'USS Iona', '491353472'),
('is300', '2001 Lexis IS300', '344171034'),
('is350mod', '2016 Lexis is350', '761919778'),
('issi2', 'Issi', '-1177863319'),
('issi3', 'Issi Classic', '931280609'),
('issi4', 'Apocalypse Issi', '628003514'),
('issi5', 'Future Shock Issi', '1537277726'),
('issi6', 'Nightmare Issi', '1239571361'),
('issi7', 'Issi Sport', '1854776567'),
('issi8', 'Issi Rally', '1550581940'),
('italigtb', 'Itali GTB', '-2048333973'),
('italigtb2', 'Itali GTB Custom', '-482719877'),
('italigto', 'Itali GTO', '-331467772'),
('italirsx', 'Itali RSX', '-1149725334'),
('iwagen', 'I-Wagen', '662793086'),
('jackal', 'Jackal', '-624529134'),
('jagxjs80', '1988 Panther Xs80', '1993373021'),
('james', 'DDG-151 Nathan Joel', '-291649400'),
('jb700', 'JB 700', '1051415893'),
('jb7002', 'JB 700W', '394110044'),
('jesko', '2023 Kongtech Presto', '-604287337'),
('jester', 'Jester', '-1297672541'),
('jester2', 'Jester (Racecar)', '-1106353882'),
('jester3', 'Jester Classic', '-214906006'),
('jester4', 'Jester RR', '-1582061455'),
('jester5', 'Jester RR Widebody', '1484920335'),
('jet', 'Jet', '1058115860'),
('jetmax', 'Jetmax', '861409633'),
('journey', 'Journey', '-120287622'),
('journey2', 'Zirconium, Journey', '-1627077503'),
('jp12', 'Rover Wrangler', '-1887798322'),
('jubilee', 'Jubilee', '461465043'),
('judger', '2019 Judge X', '-153098439'),
('jugular', 'Jugular', '-208911803'),
('jzx100', 'Typhoon Pursuer Drift', '-1838922510'),
('k22n', '2023 Hyindia Mona', '-1252811363'),
('ka52a', 'KA-52 Hoax-B', '1024243385'),
('kalahari', 'Kalahari', '92612664'),
('kamacho', 'Kamacho', '-121446169'),
('kanjo', 'Blista Kanjo', '409049982'),
('kanjosj', 'Kanjo SJ', '-64075878'),
('kawac2', 'Kasaki C-2', '-1977751928'),
('kawasaki', 'Kawasaki Concurs 14P', '-1311812071'),
('keyvanyrs6', 'RS-6 Avant 2022', '637656495'),
('khamelion', 'Khamelion', '544021352'),
('khanjali', 'TM-02 Khanjali', '-1435527158'),
('komoda', 'Komoda', '-834353991'),
('kosatka', 'Kosatka', '1336872304'),
('krieger', 'Krieger', '-664141241'),
('kuruma', 'Kuruma', '-1372848492'),
('kuruma2', 'Kuruma (Armored)', '410882957'),
('l35', 'Walton L35', '-1763675285'),
('ladybird6str', 'VW Ladybug', '-955220795'),
('lamodels', '2015 Tesla Model S', '1581555917'),
('landstalker', 'Landstalker', '1269098716'),
('landstalker2', 'Landstalker XL', '-838099166'),
('lanex400', '2008 Mistral Evolution X FQ-400', '759625212'),
('lanzador', '2024 Fettuccini Brocca', '-1437415387'),
('lazer', 'P-996 LAZER', '-1281684762'),
('lc500', 'Lexis LC500', '689090322'),
('lcm8', 'Bavaria G-Force Fury ', '2045537284'),
('le7b', 'RE-7B', '-1232836011'),
('lectro', 'Lectro', '640818791'),
('levante', 'Maseratti Levanto', '468704959'),
('lguard', 'Lifeguard', '469291905'),
('lhuracant', 'Rambarini Hurricane', '-797101702'),
('limo2', 'Turreted Limo', '-114627507'),
('lm87', 'LM87', '-10917683'),
('locust', 'Locust', '-941272559'),
('longfin', 'Longfin', '1861786828'),
('lowbar', '2023 Low Bar', '-1218829471'),
('lurcher', 'Lurcher', '2068293287'),
('luxor', 'Luxor', '621481054'),
('luxor2', 'Luxor Deluxe', '-1214293858'),
('lwcla45', '2020 Mercia-AMG A 45 4MATIC Freedom Stroll', '-2136446391'),
('lwgtr', 'Freedom Stroll GTR', '590709306'),
('lynx', 'Lynx', '482197771'),
('lynxgpr', 'Jinx GPR', '-269970895'),
('m2f22', 'Bavaria F22', '-747269546'),
('m3e30', '1989 BMV E30', '-1059188217'),
('m3f80', '1999 Bavaria M3 F80', '-580610645'),
('m3wb', '1996 Bravaria Editon 3', '-2020653691'),
('m7cstm', '2022 Bavaria 770s', '2001038975'),
('m983', 'M983 HEMTT', '814559556'),
('mache21', '2021 Stallion Rock 3 EV', '-283333597'),
('mamba', 'Mamba', '-1660945322'),
('mammatus', 'Mammatus', '-1746576111'),
('manana', 'Manana', '-2124201592'),
('manana2', 'Manana Custom', '1717532765'),
('manchez', 'Manchez', '-1523428744'),
('manchez2', 'Manchez Scout', '1086534307'),
('manchez3', 'Manchez Scout C', '1384502824'),
('mansc8', 'Chevoler Corvette C8', '-862822037'),
('mansm4', '2022 Bavaria M4 Competition', '1564933974'),
('mansq60', '2020 Bavaria M4 Infinity Q60 Black S', '-562789253'),
('manssrt', 'Dog Charging Heavencat', '-679543581'),
('marquis', 'Marquis', '-1043459709'),
('marshall', 'Marshall', '1233534620'),
('massacro', 'Massacro', '-142942670'),
('massacro2', 'Massacro (Racecar)', '-631760477'),
('maverick', 'Maverick', '-1660661558'),
('mc20h', '2023 Mazerosa GT M20', '-1878411025'),
('mclp1', 'McKaren P1', '-47001720'),
('mcqueen', 'Lightning McQueen (Epic)', '77001602'),
('menacer', 'Menacer', '2044532910'),
('mesa', 'Mesa', '914654722'),
('mesa2', 'Mesa', '-748008636'),
('mesa3', 'Mesa', '-2064372143'),
('metrotrain', 'Freight Train', '868868440'),
('mgt', 'Stallion GT', '-1432034260'),
('mh6', 'MH6 Helicopter', '906515397'),
('mi8cargo', 'Mil Mi-8 Cargo/Trooptransport', '-1856659443'),
('michelli', 'Michelli GT', '1046206681'),
('microlight', 'Ultralight', '-1763555241'),
('mig29a', 'Mig-29A Pivot', '513887552'),
('miljet', 'Miljet', '165154707'),
('minitank', 'Invade and Persuade Tank', '-1254331310'),
('minivan', 'Minivan', '-310465116'),
('minivan2', 'Minivan Custom', '-1126264336'),
('mixer', 'Mixer', '-784816453'),
('mixer2', 'Mixer', '475220373'),
('mogul', 'Mogul', '-749299473'),
('molotok', 'V-65 Molotok', '1565978651'),
('monroe', 'Monroe', '-433375717'),
('monster', 'Monster', '-845961253'),
('monster3', 'Apocalypse Sasquatch', '1721676810'),
('monster4', 'Future Shock Sasquatch', '840387324'),
('monster5', 'Nightmare Sasquatch', '-715746948'),
('monstrociti', 'MonstroCiti', '802856453'),
('montecarlo', '1988 Hevy Montecristo', '1845245771'),
('moonbeam', 'Moonbeam', '525509695'),
('moonbeam2', 'Moonbeam Custom', '1896491931'),
('mower', 'Lawn Mower', '1783355638'),
('mq9', 'MQ-9 Harvester UAV', '-1790730702'),
('mr2', '1993 Typhoon MR2', '-282505576'),
('ms1', '2017 Stormseeker S one', '-859665685'),
('mst', '2013 Falcon Stallion Shelby GT500', '162432206'),
('mule', 'Mule', '904750859'),
('mule2', 'Mule', '-1050465301'),
('mule3', 'Mule', '-2052737935'),
('mule4', 'Mule Custom', '1945374990'),
('mule5', 'Mule', '1343932732'),
('mustang', 'Stallion Speed Unit', '-1228399550'),
('mx5hr', '2023 Mazerunner Track', '784544772'),
('mxpan', '2016 Madza MX-5 Pandem', '1323262305'),
('na6', '1999 Madza Miata', '-1539291163'),
('nazgul', '2022 Harleway Softrear Fatbody', '595848268'),
('nbjm2', '2023 Bravaria W2', '171420343'),
('nebula', 'Nebula Turbo', '-882629065'),
('nemesis', 'Nemesis', '-634879114'),
('neo', 'Neo', '-1620126302'),
('neon', 'Neon', '-1848994066'),
('nero', 'Nero', '1034187331'),
('nero2', 'Nero Custom', '1093792632'),
('newsmav', 'Weazel News Maverick', '-1470089635'),
('newsvan', 'Rumpo Weazel News Van', '-74027062'),
('newsvan2', 'Mercia Weazel News Van', '79613282'),
('nightblade', 'Nightblade', '-1606187161'),
('nightshade', 'Nightshade', '-1943285540'),
('nightshark', 'Nightshark', '433954513'),
('nimbus', 'Nimbus', '-1295027632'),
('ninef', '9F', '1032823388'),
('ninef2', '9F Cabrio', '-1461482751'),
('ninja300', 'Kasaki Shinobi', '913933132'),
('niobe', 'Niobe', '1881415402'),
('nisgtir', '1990 Nihon Sunny GTI-R', '-2040001703'),
('nokota', 'P-45 Nokota', '1036591958'),
('novak', 'Novak', '-1829436850'),
('nspeedo', 'Swift Van', '1954121213'),
('ocnetrongt18', 'Orion RS E-Tron GT', '653017430'),
('omnis', 'Omnis', '-777172681'),
('omnisegt', 'Omnis e-GT', '-505223465'),
('openwheel1', 'BR8', '1492612435'),
('openwheel2', 'DR1', '1181339704'),
('oppressor', 'Oppressor', '884483972'),
('oppressor2', 'Oppressor Mk II', '2069146067'),
('oracle', 'Oracle XS', '1348744438'),
('oracle2', 'Oracle', '-511601230'),
('osiris', 'Osiris', '1987142870'),
('outlaw', 'Outlaw', '408825843'),
('pa60', 'Piper Aerostar 700P', '-1092429330'),
('packer', 'Packer', '569305213'),
('palletcar', 'Pallet Lifter Supersport', '744545831'),
('panthere', 'Panthere', '2100457220'),
('panto', 'Panto', '-431692672'),
('paradise', 'Paradise', '1488164764'),
('paragon', 'Paragon R', '-447711397'),
('paragon2', 'Paragon R (Armored)', '1416466158'),
('paragon3', 'Paragon S', '-946047670'),
('pariah', 'Pariah', '867799010'),
('patriot', 'Patriot', '-808457413'),
('patriot2', 'Patriot Stretch', '-420911112'),
('patriot3', 'Patriot Mil-Spec', '-670086588'),
('patriotaa', 'Patriot Missile Trailer', '-1585989636'),
('patriotradar', 'Patriot Radar Trailer', '-63997480'),
('patrolboat', 'Kurtz 31 Patrol Boat', '-276744698'),
('patty', 'Burger PD Car Amphibious', '475599196'),
('pavelow', 'MH-53J Pave Low III', '1366597237'),
('pbike', 'Police Bicycle', '1077822991'),
('pbus', 'Police Prison Bus', '-2007026063'),
('pbus2', 'Festival Bus', '345756458'),
('pcj', 'PCJ 600', '-909201658'),
('pdblazer', '1991 Chevie Police K5 Blazer', '1861746537'),
('pdenduro', 'PD Enduro Motercycle', '-359338691'),
('pdtaycan', '2023 Push Taygan', '1332189938'),
('peanut', 'Tiny Peanut', '-148559974'),
('peel50police', 'Peel, P50', '1097351935'),
('penetrator', 'Penetrator', '-1758137366'),
('penumbra', 'Penumbra', '-377465520'),
('penumbra2', 'Penumbra FF', '-631322662'),
('peyote', 'Peyote', '1830407356'),
('peyote2', 'Peyote Gasser', '-1804415708'),
('peyote3', 'Peyote Custom', '1107404867'),
('pfister811', '811', '-1829802492'),
('phantom', 'Phantom', '-2137348917'),
('phantom2', 'Phantom Wedge', '-1649536104'),
('phantom3', 'Phantom Custom', '177270108'),
('phantom4', 'Phantom', '-129283887'),
('phantomday', 'Phantom Day Tractor', '-303604192'),
('phantomflattop', 'Phantom FlatTop', '-441645134'),
('phantomoldschool', 'Phantom Old School', '943734638'),
('phoenix', 'Phoenix', '-2095439403'),
('picador', 'Picador', '1507916787'),
('pigalle', 'Pigalle', '1078682497'),
('pipistrello', 'Pipistrello', '-223461503'),
('pizzaboy', 'Pizza Boy', '1968807591'),
('podracer', 'Anakin Skywalker\'s Podracer', '-857301385'),
('polcaracara', 'Caracara Pursuit', '-1948949064'),
('polcoquette4', 'Coquette D10 Pursuit', '2042703219'),
('poldominator10', 'Dominator FX Interceptor', '-773802025'),
('poldorado', 'Dorado Cruiser', '-1628000569'),
('polfaction2', 'Outreach Faction', '1891140410'),
('polgauntlet', 'Gauntlet Interceptor', '-1233767450'),
('polgreenwood', 'Greenwood Cruiser', '1737348074'),
('police', 'Police Cruiser', '2046537925'),
('police2', 'Police Cruiser', '-1627000575'),
('police3', 'Police Cruiser', '1912215274'),
('police4', 'Unmarked Cruiser', '-1973172295'),
('police5', 'Stanier LE Cruiser', '-1674384553'),
('policeb', 'Police Bike', '-34623805'),
('policeold1', 'Police Rancher', '-1536924937'),
('policeold2', 'Police Roadcruiser', '-1779120616'),
('policet', 'Police Transporter', '456714581'),
('policet3', 'Burrito (Bail Enforcement)', '-1444856003'),
('polimpaler5', 'Impaler SZ Cruiser', '1249425552'),
('polimpaler6', 'Impaler LX Cruiser', '1452003510'),
('polmav', 'Police Maverick', '353883353'),
('polnspeedo', 'Transporter', '941471002'),
('polterminus', 'Terminus Patrol', '-1321131184'),
('pony', 'Pony', '-119658072'),
('pony2', 'Pony', '943752001'),
('por959', '1987 Pork 959', '819223450'),
('postlude', 'Postlude', '-294678663'),
('potty', 'Motor Potty', '-394762736'),
('pounder', 'Pounder', '2112052861'),
('pounder2', 'Pounder Custom', '1653666139'),
('powersurge', 'Powersurge', '-1386336041'),
('prairie', 'Prairie', '-1450650718'),
('pranger', 'Park Ranger', '741586030'),
('predator', 'Police Predator', '-488123221'),
('predator1', 'Predator1', '-403066713'),
('predator2', 'EMS Rescue Boat', '1766503135'),
('prelude2', '1993 Harmonia Preluge', '681420266'),
('premier', 'Premier', '-1883869285'),
('previon', 'Previon', '1416471345'),
('primo', 'Primo', '-1150599089'),
('primo2', 'Primo Custom', '-2040426790'),
('proptrailer', 'Proptrailer', '356391690'),
('prototipo', 'X80 Proto', '2123327359'),
('pulse', '2008 Unity Pulse', '-1722343009'),
('pyro', 'Pyro', '-1386191424'),
('r1', 'Kasaki R1', '1474015055'),
('r300', '300R', '1076201208'),
('r32', '1993 Nihon BNR32', '-1942693832'),
('r32l', 'Nihon Skyline GT-R R32', '1342770207'),
('r34', 'Nihon GTR (R34)', '-1278105743'),
('r35', 'Nihon GTR (R35)', '-980169995'),
('r820', 'Orion R8', '-143695728'),
('radi', 'Radius', '-1651067813'),
('raiden', 'Raiden', '-1529242755'),
('raiju', 'F-160 Raiju', '239897677'),
('raketrailer', 'Trailer', '390902130'),
('rallytruck', 'Dune', '-2103821244'),
('ramflatbed', 'PD Tow truck', '-215757382'),
('ramtrx21', '2021 Demon Slam', '1725292264'),
('rancherxl', 'Rancher XL', '1645267888'),
('rancherxl2', 'Rancher XL', '1933662059'),
('ranger2pd', 'PD Ranger ATV', '876832893'),
('rapidgt', 'Rapid GT', '-1934452204'),
('rapidgt2', 'Rapid GT', '1737773231'),
('rapidgt3', 'Rapid GT Classic', '2049897956'),
('raptor', 'Raptor', '-674927303'),
('ratbike', 'Rat Bike', '1873600305'),
('ratel', 'Ratel', '-536105557'),
('ratloader', 'Rat-Loader', '-667151410'),
('ratloader2', 'Rat-Truck', '-589178377'),
('rcbandito', 'RC Bandito', '-286046740'),
('reagpr', 'Pegassi Reaper', '-1006888373'),
('reaper', 'Reaper', '234062309'),
('rebel', 'Rusty Rebel', '-1207771834'),
('rebel2', 'Rebel', '-2045594037'),
('rebla', 'Rebla GTS', '83136452'),
('redbull21', 'Greenbull F2 2021 RB16B', '-1976833278'),
('reever', 'Reever', '1993851908'),
('regina', 'Regina', '-14495224'),
('remus', 'Remus', '1377217886'),
('rentalbus', 'Rental Shuttle Bus', '-1098802077'),
('retinue', 'Retinue', '1841130506'),
('retinue2', 'Retinue Mk II', '2031587082'),
('revolter', 'Revolter', '-410205223'),
('rhapsody', 'Rhapsody', '841808271'),
('rhinehart', 'Rhinehart', '-1855505138'),
('rhino', 'Rhino Tank', '782665360'),
('riata', 'Riata', '-1532697517'),
('rimac', 'Rimac Nevera 2021', '-1920398395'),
('riot', 'Police Riot', '-1205689942'),
('riot2', 'RCV', '-1693015116'),
('ripley', 'Ripley', '-845979911'),
('rmod240sx', '1990 Nihon 240sx Pandem', '-221892567'),
('rmodbiposto', '2020 Abert 695 Biposto', '-2033141190'),
('rmodcamaro69', '1969 Chefboyardee Camero', '-786331039'),
('rmodcharger', '2020 Charge Dodger Hellcat', '-1547840082'),
('rmodescort', '1996 Falcon Escort RS Cosworth', '1238608526'),
('rmodgt63', 'Mercia AMG', '980885719'),
('rmodlfa', '2010 Lexis LFA', '-837708260'),
('rmodm3e36', 'BMV M3 E36 V8 Biturbo', '47055373'),
('rmodmi8lb', 'Bavaria I8 Freedom Stroll', '-1476696782'),
('rmodmk7', 'Var MK7', '-1222347999'),
('rmodmustang', 'Stallion GT Racing', '350464372'),
('rmodrover', '2020 Ranger Rove Mansory', '-259063082'),
('rmodsilvia', 'Nikon Silvia (S15) Garage Door Kit', '1455731927'),
('rmodsuprapandem', '2020 Super Pandem', '1019021244'),
('rmodtracktor', 'Prime Gear Track-Tor', '168163693'),
('rmodx6', '2018 Bavaria X6M F16 Widebuild', '2045784380'),
('rmodz350pandem', '2008 Nihon 350z Pandem', '-1321588406'),
('rmodzl1', '2016 Chefboyardee Camero ZL1 Widebody', '-1293596973'),
('rocoto', 'Rocoto', '2136773105'),
('rogue', 'Rogue', '-975345305'),
('roma22', '2022 Flamestrike Romer', '-1257057490'),
('romero', 'Romero Hearse', '627094268'),
('royalnaboo', 'Naboo Royal Cruiser', '-1290605516'),
('rq4', 'RQ-4 UAV', '-637943082'),
('rrocket', 'Rampant Rocket', '916547552'),
('rs3s20', '2020 Orion RS3', '-1467706595'),
('rs4avant', 'Orion RS4', '-2019421579'),
('rs520', '2020 Orion 5-RS', '-235770318'),
('rs62', 'Orion RS62', '-134949878'),
('rt3000', 'RT3000', '-452604007'),
('rubble', 'Rubble', '-1705304628'),
('ruffian', 'Ruffian', '-893578776'),
('ruiner', 'Ruiner', '-227741703'),
('ruiner2', 'Ruiner 2000', '941494461'),
('ruiner3', 'Ruiner', '777714999'),
('ruiner4', 'Ruiner ZZ-8', '1706945532'),
('rumpo', 'Rumpo', '1162065741'),
('rumpo2', 'Rumpo', '-1776615689'),
('rumpo3', 'Rumpo Custom', '1475773103'),
('ruston', 'Ruston', '719660200'),
('rx811', '2008 Madza RX8', '1459731965'),
('s281', '2009 Silvermoon Stallion', '-771791367'),
('s63amg18', '2018 Midnight Sport 63', '360420537'),
('s80', 'S80RR', '-324618589'),
('s95', 'S95', '1133471123'),
('sabregt', 'Sabre Turbo', '-1685021548'),
('sabregt2', 'Sabre Turbo Custom', '223258115'),
('sadler', 'Sadler', '-599568815'),
('sadler2', 'Sadler', '734217681'),
('sanchez', 'Sanchez (livery)', '788045382'),
('sanchez2', 'Sanchez', '-1453280962'),
('sanctus', 'Sanctus', '1491277511'),
('sancyb4', 'Phancy B4', '-1578648518'),
('sandking', 'Sandking XL', '-1189015600'),
('sandking2', 'Sandking SWB', '989381445'),
('santa', 'Santas Sled', '-1734169614'),
('savage', 'Savage', '-82626025'),
('savestra', 'Savestra', '903794909'),
('sbrwrx', 'Impulse WRX STI 2007 WRC', '-1111150036'),
('sc1', 'SC1', '1352136073'),
('scarab', 'Apocalypse Scarab', '-1146969353'),
('scarab2', 'Future Shock Scarab', '1542143200'),
('scarab3', 'Nightmare Scarab', '-579747861'),
('schafter2', 'Schafter', '-1255452397'),
('schafter3', 'Schafter V12', '-1485523546'),
('schafter4', 'Schafter LWB', '1489967196'),
('schafter5', 'Schafter V12 (Armored)', '-888242983'),
('schafter6', 'Schafter LWB (Armored)', '1922255844'),
('schlagen', 'Schlagen GT', '-507495760'),
('schwarzer', 'Schwartzer', '-746882698'),
('scorcher', 'Scorcher', '-186537451'),
('scramjet', 'Scramjet', '-638562243'),
('scrap', 'Scrap Truck', '-1700801569'),
('seabreeze', 'Seabreeze', '-392675425'),
('seashark', 'Seashark', '-1030275036'),
('seashark2', 'Seashark', '-616331036'),
('seashark3', 'Seashark', '-311022263'),
('seasparrow', 'Sea Sparrow', '-726768679'),
('seasparrow2', 'Sparrow', '1229411063'),
('seasparrow3', 'Sparrow', '1593933419'),
('segway', 'Segway (Police)', '1679093186'),
('segwayciv', 'Segway', '-256672374'),
('seminole', 'Seminole', '1221512915'),
('seminole2', 'Seminole Frontier', '-1810806490'),
('sentinel', 'Sentinel XS', '1349725314'),
('sentinel2', 'Sentinel', '873639469'),
('sentinel3', 'Sentinel', '1104234922'),
('sentinel4', 'Sentinel Classic Widebody', '-1356880839'),
('serrano', 'Serrano', '1337041428'),
('seven70', 'Seven-70', '-1757836725'),
('sf50vision', 'Stratus SF50', '219698136'),
('shamal', 'Shamal', '-1214505995'),
('sheava', 'ETR1', '819197656'),
('shelby20', '2020 Fork Mustard GT500', '-2083787888'),
('shelbylbwk', 'Fork Shelber Libibi Walk Edition', '373989014'),
('sheriff', 'Sheriff Cruiser', '-1683328900'),
('sheriff2', 'Sheriff SUV', '1922257928'),
('shinobi', 'Shinobi', '1353120668'),
('shotaro', 'Shotaro', '-405626514'),
('silv86', 'Silverline 86', '-304124483'),
('silvias15', '15 Silver', '-1390169318'),
('skart', '2002 Mart Kart', '-1048341725'),
('skidoo800R', 'skidoo 800r', '-916482878'),
('skylift', 'Skylift', '1044954915'),
('slamtruck', 'Slamtruck', '-1045911276'),
('slamvan', 'Slamvan', '729783779'),
('slamvan2', 'Lost Slamvan', '833469436'),
('slamvan3', 'Slamvan Custom', '1119641113'),
('slamvan4', 'Apocalypse Slamvan', '-2061049099'),
('slamvan5', 'Future Shock Slamvan', '373261600'),
('slamvan6', 'Nightmare Slamvan', '1742022738'),
('slave', 'Bound Rider', '-133970931'),
('sm722', 'SM722', '775514032'),
('snatchback', '2023 Hyena Snatchback', '1213239367'),
('sovereign', 'Sovereign', '743478836'),
('specter', 'Specter', '1886268224'),
('specter2', 'Specter Custom', '1074745671'),
('speeder', 'Speeder', '231083307'),
('speeder2', 'Speeder', '437538602'),
('speedo', 'Speedo', '-810318068'),
('speedo2', 'Clown Van', '728614474'),
('speedo4', 'Speedo Custom', '219613597'),
('speedo5', 'Speedo Custom', '-44799464'),
('spirit', 'B-2A Stealth Bomber', '445865749'),
('spitfire', 'Fireblade Mk.IIB', '-1745779170'),
('springer', '2000 Harleyway Heritage Springer', '-1016279499'),
('squaddie', 'Squaddie', '-102335483'),
('squalo', 'Squalo', '400514754'),
('sshuttle', 'Space Shuttle', '513796448'),
('sspres', 'Transport Suburbia', '658490459'),
('stafford', 'Stafford', '321186144'),
('stalion', 'Stallion', '1923400478'),
('stalion2', 'Burger Shot Stallion', '-401643538'),
('stanier', 'Stanier', '-1477580979'),
('stanier5', 'Rapid Stanier Off Road', '1595740562'),
('stardestroy', 'Star Destroyer', '495830928'),
('starling', 'LF-22 Starling', '-1700874274'),
('stinger', 'Stinger', '1545842587'),
('stingergt', 'Stinger GT', '-2098947590'),
('stingertt', 'Itali GTO Stinger TT', '1447690049'),
('stockade', 'Stockade', '1747439474'),
('stockade3', 'Stockade', '-214455498'),
('stratum', 'Stratum', '1723137093'),
('streamer216', 'Streamer216', '191916658'),
('streeetch', 'Streeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeetch', '804243323'),
('streetglide', 'Harleyway Streetglide', '1884657834'),
('streiter', 'Streiter', '1741861769'),
('stretch', 'Stretch', '-1961627517'),
('strikeforce', 'B-11 Strikeforce', '1692272545'),
('stromberg', 'Stromberg', '886810209'),
('stryder', 'Stryder', '301304410'),
('stunt', 'Mallard', '-2122757008'),
('su27', 'SU-27 Flanker', '-1969666614'),
('submersible', 'Submersible', '771711535'),
('submersible2', 'Kraken', '-1066334226'),
('subn', 'Suburbia', '-701263831'),
('subtitan', 'Titan Submersible', '1239723846'),
('subwrx', 'Subari WRX STI', '-1298373790'),
('sugoi', 'Sugoi', '987469656'),
('sultan', 'Sultan', '970598228'),
('sultan2', 'Sultan Classic', '872704284'),
('sultan3', 'Sultan RS Classic', '-291021213'),
('sultanrs', 'Sultan RS', '-295689028'),
('suntrap', 'Suntrap', '-282946103'),
('superd', 'Super Diamond', '1123216662'),
('supervolito', 'Weazel News Supervolito', '710198397'),
('supervolito2', 'SuperVolito Carbon', '-1671539132'),
('supra2', 'Typhoon Sura', '-2120897359'),
('surano', 'Surano', '384071873'),
('surfer', 'Surfer', '699456151'),
('surfer2', 'Surfer', '-1311240698'),
('surfer3', 'Surfer Custom', '-1035489563'),
('surge', 'Surge', '-1894894188'),
('swathel', 'SWAT Blackhawk', '1037059299'),
('swift', 'Swift', '-339587598'),
('swift2', 'Swift Deluxe', '1075432268'),
('swinger', 'Swinger', '500482303'),
('t20', 'T20', '1663218586'),
('taco', 'Taco Van', '1951180813'),
('taco2', 'Cherry Popper Ice Cream Truck', '-409512831'),
('tahoma', 'Tahoma Coupe', '-461850249'),
('tailgater', 'Tailgater', '-1008861746'),
('tailgater2', 'Tailgater S', '-1244461404'),
('taipan', 'Taipan', '-1134706562'),
('tampa', 'Tampa', '972671128'),
('tampa2', 'Drift Tampa', '-1071380347'),
('tampa3', 'Weaponized Tampa', '-1210451983'),
('tanker', 'Trailer', '-730904777'),
('tanker2', 'Tanker 2', '1956216962'),
('tankercar', 'Freight Train', '586013744'),
('taxi', 'Taxi', '-956048545'),
('technical', 'Technical', '-2096818938'),
('technical2', 'Technical Aqua', '1180875963'),
('technical3', 'Technical Custom', '1356124575'),
('technical4', 'Karin Technical', '1695939105'),
('tempesta', 'Tempesta', '272929391'),
('templar', 'Harleyway', '584706112'),
('tenf', '10F', '-893984159'),
('tenf2', '10F Widebody', '274946574'),
('terbyte', 'Terrorbyte', '-1988428699'),
('terminus', 'Terminus', '167522317'),
('teslamodels', 'Telsa Model S', '-979071501'),
('tezeract', 'Tezeract', '1031562256'),
('thrax', 'Thrax', '1044193113'),
('thrust', 'Thrust', '1836027715'),
('thruster', 'Thruster', '1489874736'),
('tiefighterx', 'TIE Fighter', '520411583'),
('tigon', 'Tigon', '-1358197432'),
('tiptruck', 'Tipper', '48339065'),
('tiptruck2', 'Tipper', '-947761570'),
('titan', 'Titan', '1981688531'),
('titan2', 'Titan 250 D', '858355070'),
('titanbyv', 'Nihon Titan', '-1675902777'),
('titanic2', 'RMS Titanic', '-87525510'),
('toreador', 'Toreador', '1455990255'),
('torero', 'Torero', '1504306544'),
('torero2', 'Torero XO', '-165394758'),
('tornado', 'Tornado', '464687292'),
('tornado2', 'Tornado', '1531094468'),
('tornado3', 'Tornado', '1762279763'),
('tornado4', 'Tornado', '-2033222435'),
('tornado5', 'Tornado Custom', '-1797613329'),
('tornado6', 'Tornado Rat Rod', '-1558399629'),
('toro', 'Toro', '1070967343'),
('toro2', 'Toro', '908897389'),
('toros', 'Toros', '-1168952148'),
('tourbus', 'Tour Bus', '1941029835'),
('towcustom', 'MTL Towtruck Custom', '1171524508'),
('towtruck', 'Tow Truck', '-1323100960'),
('towtruck2', 'Tow Truck', '-442313018'),
('towtruck3', 'Tow Truck', '-671564942'),
('towtruck4', 'Tow Truck', '-902029319'),
('toy86', '2018 Typhoon GT86', '-1943578229'),
('toysupmk4', '1998 Typhoon Sura Mk4 Wide Body', '-1062758007'),
('tr2', 'Trailer', '2078290630'),
('tr22', 'Telsa Roamer', '1197361861'),
('tr3', 'Trailer', '1784254509'),
('tr4', 'Trailer', '2091594960'),
('tractor', 'Tractor', '1641462412'),
('tractor2', 'Fieldmaster', '-2076478498'),
('tractor3', 'Fieldmaster', '1445631933'),
('trailerflat2', 'Medium Vehicle Trailer', '950412192'),
('trailerlarge', 'Mobile Operations Center', '1502869817'),
('trailerlogs', 'Trailer', '2016027501'),
('trailers', 'Trailer', '-877478386'),
('trailers2', 'Trailer', '-1579533167'),
('trailers3', 'Trailer', '-2058878099'),
('trailers4', 'Trailer', '-1100548694'),
('trailers5', 'Trailer', '-1334453816'),
('trailersmall', 'Trailer', '712162987'),
('trailersmall2', 'Anti-Aircraft Trailer', '-1881846085'),
('trash', 'Trashmaster', '1917016601'),
('trash2', 'Trashmaster', '-1255698084'),
('trash3', 'Trash Truck', '1917062038'),
('trflat', 'Trailer', '-1352468814'),
('trhawk', 'Rover Track-Hawk', '231217483'),
('tribike', 'Whippet Race Bike', '1127861609'),
('tribike2', 'Endurex Race Bike', '-1233807380'),
('tribike3', 'Tri-Cycles Race Bike', '-400295096'),
('trophytruck', 'Trophy Truck', '101905590'),
('trophytruck2', 'Desert Raid', '-663299102'),
('tropic', 'Tropic', '290013743'),
('tropic2', 'Tropic', '1448677353'),
('tropos', 'Tropos Rallye', '1887331236'),
('tsgr20', '20 Typhoon Sura', '1762839497'),
('tts', '2015 Orion TTS', '-1747980967'),
('tug', 'Tug', '-2100640717'),
('tula', 'Tula', '1043222410'),
('tulip', 'Tulip', '1456744817'),
('tulip2', 'Tulip M-100', '268758436'),
('tunak', '2010 TVS Tuk Tuk', '917028873'),
('turismo2', 'Turismo Classic', '-982130927'),
('turismo3', 'Turismo Omaggio', '-122993285'),
('turismor', 'Turismo R', '408192225'),
('tvtrailer', 'Trailer', '-1770643266'),
('tvtrailer2', 'Trailer', '471034616'),
('type1', 'Truffade Alpha-Type', '-1218882528'),
('tyrant', 'Tyrant', '-376434238'),
('tyrus', 'Tyrus', '2067820283'),
('umoracle', 'Unmarked Oracle', '-1992613535'),
('uranus', 'Uranus LozSpeed', '1534326199'),
('urus', 'Rambarini Uros', '-520214134'),
('utillitruck', 'Utility Truck', '516990260'),
('utillitruck2', 'Utility Truck', '887537515'),
('utillitruck3', 'Utility Truck', '2132890591'),
('v60', '2018 V Wagon TT', '-1379621977'),
('vacca', 'Vacca', '338562499'),
('vader', 'Vader', '-140902153'),
('vagner', 'Vagner', '1939284556'),
('vagrant', 'Vagrant', '740289177'),
('valciv18', '2018 Demon Energizer', '-1057531381'),
('valkyrie', 'Valkyrie', '-1600252419'),
('valkyrie2', 'Valkyrie MOD.0', '1543134283'),
('valkyrietp', 'Astmha Martin, Valkyrie', '984018554'),
('valkyrietp2', 'Astmha Martin, Valkyrie 2', '-629395704'),
('valor18ch', '2018 Charge Dodger', '1424881593'),
('valor18ta', '2018 Chevie Taiga', '-240286507'),
('valor20ram', '2020 Ram 3500 HD', '-1569277087'),
('valorcap', '2013 Chevie Capricorn', '-1605045090'),
('valorf250', '2020 Falcon F250 Heavy Duty', '-1292882222'),
('vamos', 'Vamos', '-49115651'),
('vectre', 'Vectre', '-1540373595'),
('velar', 'Range Rambler Velar', '542147885'),
('velum', 'Velum', '-1673356438'),
('velum2', 'Velum 5-Seater', '1077420264'),
('verlierer2', 'Verlierer', '1102544804'),
('verus', 'Verus', '298565713'),
('vestra', 'Vestra', '1341619767'),
('vetir', 'Vetir', '2014313426'),
('veto', 'Veto Classic', '-857356038'),
('veto2', 'Veto Modern', '-1492917079'),
('vgt12', '2015 Stellar Orion GT12', '-1273978259');
INSERT INTO `vehicles` (`model_name`, `label`, `id`) VALUES
('vigero', 'Vigero', '-825837129'),
('vigero2', 'Vigero ZX', '-1758379524'),
('vigero3', 'Vigero ZX Convertible', '372621319'),
('vigilante', 'Vigilante', '-1242608589'),
('vindicator', 'Vindicator', '-1353081087'),
('virgo', 'Virgo', '-498054846'),
('virgo2', 'Virgo Classic Custom', '-899509638'),
('virgo3', 'Virgo Classic', '16646064'),
('virtue', 'Virtue', '669204833'),
('viseris', 'Viseris', '-391595372'),
('visione', 'Visione', '-998177792'),
('vivanite', 'Vivanite', '-1372798934'),
('volatol', 'Volatol', '447548909'),
('volatus', 'Volatus', '-1845487887'),
('voltic', 'Voltic', '-1622444098'),
('voltic2', 'Rocket Voltic', '989294410'),
('volva', '2010 Gnarly Stag', '-280563304'),
('voodoo', 'Voodoo Custom', '2006667053'),
('voodoo2', 'Voodoo', '523724515'),
('vorschlaghammer', 'Vorschlaghammer', '-1240172147'),
('vortex', 'Vortex', '-609625092'),
('vstr', 'V-STR', '1456336509'),
('vulcan3', '2017 Pastor Martini Vilocoraptor', '1718909989'),
('warrener', 'Warrener', '1373123368'),
('warrener2', 'Warrener HKR', '579912970'),
('washington', 'Washington', '1777363799'),
('wastelander', 'Wastelander', '-1912017790'),
('weevil', 'Weevil', '1644055914'),
('weevil2', 'Weevil Custom', '-994371320'),
('wheelchair', 'Wheelchair', '-1178021069'),
('wildtrak', '2021 Falcon Bronco', '-1180922538'),
('windsor', 'Windsor', '1581459400'),
('windsor2', 'Windsor Drop', '-1930048799'),
('winky', 'Winky', '-210308634'),
('wolfsbane', 'Wolfsbane', '-618617997'),
('wraith', 'Rolls Regal Spectre', '-1095688294'),
('wrx19', '2019 Legacy RapidStorm S', '-1423481308'),
('x3ct522', 'Cavala CT5-X Blackding', '-1205427559'),
('xa21', 'XA-21', '917809321'),
('xkgt', '2015 Jaguard XKR-S GT', '-1365403783'),
('xls', 'XLS', '1203490606'),
('xls2', 'XLS (Armored)', '-432008408'),
('xwing2', 'T-65B X-wing starfighter', '-1719218934'),
('yosemite', 'Yosemite', '1871995513'),
('yosemite1500', 'Yosemite 1500', '-1896488056'),
('yosemite2', 'Drift Yosemite', '1693751655'),
('yosemite3', 'Yosemite Custom', '67753863'),
('youga', 'Youga', '65402552'),
('youga2', 'Youga Classic', '1026149675'),
('youga3', 'Youga Custom', '1802742206'),
('youga4', 'Youga Custom', '1486521356'),
('youga5', 'Youga Custom', '-2028904199'),
('ypg205t16b', '1988 Pegasso 205 GTi Rally', '-16098358'),
('yrenault5tb', '1981 Renoir 5 Turbo Rally', '1058484733'),
('yzfr6', '2015 Yamyaha YZF-R6', '-359650641'),
('z190', '190z', '838982985'),
('z32', '1993 Nicean 300 Zebra', '624293437'),
('zeno', 'Zeno', '655665811'),
('zentorno', 'Zentorno', '-1403128555'),
('zhaba', 'Zhaba', '1284356689'),
('zion', 'Zion', '-1122289213'),
('zion2', 'Zion Cabrio', '-1193103848'),
('zion3', 'Zion Classic', '1862507111'),
('zl12017', 'Camero ZL1', '531756283'),
('zombiea', 'Zombie Bobber', '-1009268949'),
('zombieb', 'Zombie Chopper', '-570033273'),
('zombiev8', 'V8 Undead Chopper', '1668332124'),
('zorrusso', 'Zorrusso', '-682108547'),
('zr1rb', '2018 ZR1 Corvex', '235768976'),
('zr350', 'ZR350', '-1858654120'),
('zr380', 'Apocalypse ZR380', '540101442'),
('zr3802', 'Future Shock ZR380', '-1106120762'),
('zr3803', 'Nightmare ZR380', '-1478704292'),
('zr3806str', 'zr3806str', '-1786460813'),
('ztype', 'Z-Type', '758895617'),
('zx10r', 'Kasaki ZX10R', '-714386060');

-- --------------------------------------------------------

--
-- Table structure for table `votes`
--

CREATE TABLE `votes` (
  `vote_id` int(11) NOT NULL,
  `vote_week` int(11) NOT NULL DEFAULT 0,
  `voted_by` int(11) NOT NULL DEFAULT 0,
  `vote_for` int(11) NOT NULL DEFAULT 0,
  `vote` bigint(20) NOT NULL DEFAULT 0,
  `reasoning` longtext DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

--
-- Indexes for dumped tables
--

--
-- Indexes for table `announcements`
--
ALTER TABLE `announcements`
  ADD PRIMARY KEY (`announcement_id`),
  ADD KEY `announcement_id` (`announcement_id`);

--
-- Indexes for table `api_keys`
--
ALTER TABLE `api_keys`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `changes`
--
ALTER TABLE `changes`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `characters`
--
ALTER TABLE `characters`
  ADD PRIMARY KEY (`character_id`) USING BTREE,
  ADD KEY `idx_character_id` (`character_id`);

--
-- Indexes for table `character_expungements`
--
ALTER TABLE `character_expungements`
  ADD PRIMARY KEY (`expungement_id`),
  ADD UNIQUE KEY `expungement_id` (`expungement_id`);

--
-- Indexes for table `character_notes`
--
ALTER TABLE `character_notes`
  ADD PRIMARY KEY (`note_id`),
  ADD UNIQUE KEY `note_id` (`note_id`);

--
-- Indexes for table `character_pictures`
--
ALTER TABLE `character_pictures`
  ADD PRIMARY KEY (`picture_id`) USING BTREE,
  ADD UNIQUE KEY `picture_id` (`picture_id`);

--
-- Indexes for table `character_points`
--
ALTER TABLE `character_points`
  ADD PRIMARY KEY (`reset_id`) USING BTREE,
  ADD UNIQUE KEY `expungement_id` (`reset_id`) USING BTREE;

--
-- Indexes for table `character_properties`
--
ALTER TABLE `character_properties`
  ADD PRIMARY KEY (`property_id`),
  ADD UNIQUE KEY `property_id` (`property_id`);

--
-- Indexes for table `character_tags`
--
ALTER TABLE `character_tags`
  ADD PRIMARY KEY (`tag_id`),
  ADD UNIQUE KEY `tag_id` (`tag_id`);

--
-- Indexes for table `character_vehicles`
--
ALTER TABLE `character_vehicles`
  ADD PRIMARY KEY (`vehicle_id`),
  ADD UNIQUE KEY `vehicle_id` (`vehicle_id`);

--
-- Indexes for table `character_vehicle_finance`
--
ALTER TABLE `character_vehicle_finance`
  ADD PRIMARY KEY (`finance_id`);

--
-- Indexes for table `character_warrants_bolos`
--
ALTER TABLE `character_warrants_bolos`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `demotions`
--
ALTER TABLE `demotions`
  ADD PRIMARY KEY (`demotions_id`),
  ADD UNIQUE KEY `demotions_id_UNIQUE` (`demotions_id`);

--
-- Indexes for table `incidents`
--
ALTER TABLE `incidents`
  ADD PRIMARY KEY (`incident_id`),
  ADD UNIQUE KEY `incident_id_UNIQUE` (`incident_id`);

--
-- Indexes for table `incident_arrests`
--
ALTER TABLE `incident_arrests`
  ADD PRIMARY KEY (`arrest_id`),
  ADD UNIQUE KEY `arrest_id` (`arrest_id`);

--
-- Indexes for table `incident_arrests_charges`
--
ALTER TABLE `incident_arrests_charges`
  ADD PRIMARY KEY (`charge_id`),
  ADD UNIQUE KEY `charge_id` (`charge_id`);

--
-- Indexes for table `incident_arrests_items`
--
ALTER TABLE `incident_arrests_items`
  ADD PRIMARY KEY (`item_id`),
  ADD UNIQUE KEY `item_id` (`item_id`);

--
-- Indexes for table `incident_arrests_mugshots`
--
ALTER TABLE `incident_arrests_mugshots`
  ADD PRIMARY KEY (`mugshot_id`),
  ADD UNIQUE KEY `mugshot_id` (`mugshot_id`);

--
-- Indexes for table `incident_evidence`
--
ALTER TABLE `incident_evidence`
  ADD PRIMARY KEY (`evidence_id`),
  ADD UNIQUE KEY `evidence_id` (`evidence_id`);

--
-- Indexes for table `incident_officers`
--
ALTER TABLE `incident_officers`
  ADD PRIMARY KEY (`officers_id`),
  ADD UNIQUE KEY `officers_id_UNIQUE` (`officers_id`);

--
-- Indexes for table `incident_persons`
--
ALTER TABLE `incident_persons`
  ADD PRIMARY KEY (`persons_id`);

--
-- Indexes for table `incident_reports`
--
ALTER TABLE `incident_reports`
  ADD PRIMARY KEY (`report_id`),
  ADD UNIQUE KEY `report_id` (`report_id`),
  ADD KEY `idx_incident_reports_incident_id` (`incident_id`);

--
-- Indexes for table `incident_tags`
--
ALTER TABLE `incident_tags`
  ADD PRIMARY KEY (`tag_id`),
  ADD UNIQUE KEY `tag_id` (`tag_id`);

--
-- Indexes for table `items`
--
ALTER TABLE `items`
  ADD PRIMARY KEY (`name`);

--
-- Indexes for table `login`
--
ALTER TABLE `login`
  ADD PRIMARY KEY (`character_id`);

--
-- Indexes for table `logs`
--
ALTER TABLE `logs`
  ADD PRIMARY KEY (`logId`);

--
-- Indexes for table `penal_code_charges`
--
ALTER TABLE `penal_code_charges`
  ADD PRIMARY KEY (`charge_id`);

--
-- Indexes for table `penal_code_definitions`
--
ALTER TABLE `penal_code_definitions`
  ADD PRIMARY KEY (`definition_id`);

--
-- Indexes for table `penal_code_enhancements`
--
ALTER TABLE `penal_code_enhancements`
  ADD PRIMARY KEY (`enhancement_id`);

--
-- Indexes for table `ranks`
--
ALTER TABLE `ranks`
  ADD PRIMARY KEY (`rank_order`);

--
-- Indexes for table `roster`
--
ALTER TABLE `roster`
  ADD PRIMARY KEY (`character_id`);

--
-- Indexes for table `roster_certs`
--
ALTER TABLE `roster_certs`
  ADD PRIMARY KEY (`cert_id`),
  ADD UNIQUE KEY `cert_id` (`cert_id`);

--
-- Indexes for table `roster_changes`
--
ALTER TABLE `roster_changes`
  ADD PRIMARY KEY (`roster_change_id`),
  ADD UNIQUE KEY `roster_change_id` (`roster_change_id`);

--
-- Indexes for table `roster_doj`
--
ALTER TABLE `roster_doj`
  ADD PRIMARY KEY (`character_id`);

--
-- Indexes for table `roster_fib`
--
ALTER TABLE `roster_fib`
  ADD PRIMARY KEY (`character_id`);

--
-- Indexes for table `roster_ftp`
--
ALTER TABLE `roster_ftp`
  ADD PRIMARY KEY (`character_id`);

--
-- Indexes for table `roster_gw`
--
ALTER TABLE `roster_gw`
  ADD PRIMARY KEY (`character_id`);

--
-- Indexes for table `roster_ia`
--
ALTER TABLE `roster_ia`
  ADD PRIMARY KEY (`character_id`);

--
-- Indexes for table `roster_management`
--
ALTER TABLE `roster_management`
  ADD PRIMARY KEY (`character_id`);

--
-- Indexes for table `roster_notes`
--
ALTER TABLE `roster_notes`
  ADD PRIMARY KEY (`note_id`) USING BTREE,
  ADD UNIQUE KEY `noteId` (`note_id`) USING BTREE;

--
-- Indexes for table `roster_sahp`
--
ALTER TABLE `roster_sahp`
  ADD PRIMARY KEY (`character_id`);

--
-- Indexes for table `roster_strikes`
--
ALTER TABLE `roster_strikes`
  ADD PRIMARY KEY (`strike_id`),
  ADD UNIQUE KEY `strike_id` (`strike_id`);

--
-- Indexes for table `roster_swat`
--
ALTER TABLE `roster_swat`
  ADD PRIMARY KEY (`character_id`);

--
-- Indexes for table `sessions`
--
ALTER TABLE `sessions`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `time`
--
ALTER TABLE `time`
  ADD PRIMARY KEY (`character_id`);

--
-- Indexes for table `time_extra`
--
ALTER TABLE `time_extra`
  ADD PRIMARY KEY (`time_id`),
  ADD UNIQUE KEY `time_id` (`time_id`);

--
-- Indexes for table `vehicles`
--
ALTER TABLE `vehicles`
  ADD PRIMARY KEY (`model_name`);

--
-- Indexes for table `votes`
--
ALTER TABLE `votes`
  ADD PRIMARY KEY (`vote_id`),
  ADD UNIQUE KEY `vote_id` (`vote_id`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `announcements`
--
ALTER TABLE `announcements`
  MODIFY `announcement_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `api_keys`
--
ALTER TABLE `api_keys`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `changes`
--
ALTER TABLE `changes`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `character_expungements`
--
ALTER TABLE `character_expungements`
  MODIFY `expungement_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `character_notes`
--
ALTER TABLE `character_notes`
  MODIFY `note_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `character_pictures`
--
ALTER TABLE `character_pictures`
  MODIFY `picture_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `character_points`
--
ALTER TABLE `character_points`
  MODIFY `reset_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `character_properties`
--
ALTER TABLE `character_properties`
  MODIFY `property_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `character_tags`
--
ALTER TABLE `character_tags`
  MODIFY `tag_id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `character_vehicles`
--
ALTER TABLE `character_vehicles`
  MODIFY `vehicle_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `character_vehicle_finance`
--
ALTER TABLE `character_vehicle_finance`
  MODIFY `finance_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `character_warrants_bolos`
--
ALTER TABLE `character_warrants_bolos`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `demotions`
--
ALTER TABLE `demotions`
  MODIFY `demotions_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `incidents`
--
ALTER TABLE `incidents`
  MODIFY `incident_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `incident_arrests`
--
ALTER TABLE `incident_arrests`
  MODIFY `arrest_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `incident_arrests_charges`
--
ALTER TABLE `incident_arrests_charges`
  MODIFY `charge_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `incident_arrests_items`
--
ALTER TABLE `incident_arrests_items`
  MODIFY `item_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `incident_arrests_mugshots`
--
ALTER TABLE `incident_arrests_mugshots`
  MODIFY `mugshot_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `incident_evidence`
--
ALTER TABLE `incident_evidence`
  MODIFY `evidence_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `incident_officers`
--
ALTER TABLE `incident_officers`
  MODIFY `officers_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `incident_persons`
--
ALTER TABLE `incident_persons`
  MODIFY `persons_id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `incident_reports`
--
ALTER TABLE `incident_reports`
  MODIFY `report_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `incident_tags`
--
ALTER TABLE `incident_tags`
  MODIFY `tag_id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `logs`
--
ALTER TABLE `logs`
  MODIFY `logId` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `penal_code_charges`
--
ALTER TABLE `penal_code_charges`
  MODIFY `charge_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=1174;

--
-- AUTO_INCREMENT for table `penal_code_definitions`
--
ALTER TABLE `penal_code_definitions`
  MODIFY `definition_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=31;

--
-- AUTO_INCREMENT for table `penal_code_enhancements`
--
ALTER TABLE `penal_code_enhancements`
  MODIFY `enhancement_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=13;

--
-- AUTO_INCREMENT for table `roster_certs`
--
ALTER TABLE `roster_certs`
  MODIFY `cert_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `roster_changes`
--
ALTER TABLE `roster_changes`
  MODIFY `roster_change_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `roster_notes`
--
ALTER TABLE `roster_notes`
  MODIFY `note_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `roster_strikes`
--
ALTER TABLE `roster_strikes`
  MODIFY `strike_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `sessions`
--
ALTER TABLE `sessions`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `time_extra`
--
ALTER TABLE `time_extra`
  MODIFY `time_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `votes`
--
ALTER TABLE `votes`
  MODIFY `vote_id` int(11) NOT NULL AUTO_INCREMENT;
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
