#!/bin/sh
php -r "echo json_encode(json_decode(file_get_contents('$1')), JSON_PRETTY_PRINT);"
