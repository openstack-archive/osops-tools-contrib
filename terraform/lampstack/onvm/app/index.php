 <?php
$servername = "database";
$username = "TTTFFFdbuser";
$password = "TTTFFFdbpass";
$dbname = "decision2016";

try {
  $conn = new PDO("mysql:host=$servername;dbname=$dbname", $username, $password);
  $conn->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
  echo "Connected successfully";
}
catch(PDOException $e) {
  echo "Connection failed: " . $e->getMessage();
}
?> 