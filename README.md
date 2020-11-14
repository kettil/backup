# Backup

## First steps

```bash
# Install borgbackup over homebrew
brew install borgbackup

# Clone the repo
git clone https://github.com/kettil/backup.git ~/.backup
cd ~/.backup

# Copy the .env and borgignore files
cp -i .env-dist .env && cp -i .borgignore-dist .borgignore

# Edit the .env file
nano .env

# Initialize the backup ...
./backup.sh init

# ... and create the first backup
./backup.sh create
```

## Cronjob

To make a regular backup, the following lines must be added to the crontab.

```bash
# every half hour
*/30 * * * * ~/.backup/backup.sh create --cron > /dev/null 2>&1
# every saturday at 19:05
5 19 * * 6 ~/.backup/backup.sh check --cron > /dev/null 2>&1
# every sunday at 19:05
5 19 * * 7 ~/.backup/backup.sh prune --cron > /dev/null 2>&1
```
