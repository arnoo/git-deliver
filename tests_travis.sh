sudo groupadd git
sudo usermod -a -G git $USER

ssh-keygen
cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys

ssh-keyscan -H localhost >> ~/.ssh/known_hosts

sudo useradd -g git bob
sudo cp ~$USER/.ssh/authorized_keys ~bob/.ssh/
sudo chown bob ~bob/.ssh/authorized_keys
sudo su bob -c "ssh-keyscan -H localhost >> ~/.ssh/known_hosts"

sudo useradd alice
sudo cp ~$USER/.ssh/authorized_keys ~alice/.ssh/
sudo chown alice ~alice/.ssh/authorized_keys
sudo su alice -c "ssh-keyscan -H localhost >> ~/.ssh/known_hosts"

./tests.sh
