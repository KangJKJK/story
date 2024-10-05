#!/bin/bash

# 색상 정의
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # 색상 초기화

# 필수 함수 정의
function download_and_install {
    local url=$1
    local tar_file=$2
    local binary_name=$3
    local install_path=$4

    # URL에서 파일 다운로드
    wget $url -O /root/$tar_file
    if [ $? -ne 0 ]; then
        echo -e "${RED}다운로드 실패: $url${NC}"
        exit 1
    fi

    # 다운로드 받은 파일 압축 해제
    tar -xzvf /root/$tar_file -C /root/
    if [ $? -ne 0 ]; then
        echo -e "${RED}압축 해제 실패: /root/$tar_file${NC}"
        exit 1
    fi

    # 설치 경로 확인 및 생성 후 파일 복사
    [ ! -d "$install_path" ] && mkdir -p $install_path
    sudo cp "/root/$binary_name" "$install_path"
    if [ $? -ne 0 ]; then
        echo -e "${RED}파일 복사 실패: $binary_name${NC}"
        exit 1
    fi
}

# 필수 의존성 업데이트 및 설치
echo -e "${YELLOW}의존성 설치 중...${NC}"
sudo apt update && sudo apt-get update
sudo apt install curl git make jq build-essential gcc unzip wget lz4 aria2 pv -y

# Go 언어 설치
echo -e "${YELLOW}Go 언어 설치 중...${NC}"
cd $HOME && \
ver="1.22.0" && \
wget "https://golang.org/dl/go$ver.linux-amd64.tar.gz" && \
sudo rm -rf /usr/local/go && \
sudo tar -C /usr/local -xzf "go$ver.linux-amd64.tar.gz" && \
rm "go$ver.linux-amd64.tar.gz"

# 환경 변수 설정
echo -e "${YELLOW}환경 변수 설정 중...${NC}"
export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin
export STORY_DATA_ROOT="$HOME/go/bin"
export GETH_DATA_ROOT="$HOME/go/bin"
echo "export PATH=$PATH" >> ~/.bash_profile
echo "export STORY_DATA_ROOT=$STORY_DATA_ROOT" >> ~/.bash_profile
echo "export GETH_DATA_ROOT=$GETH_DATA_ROOT" >> ~/.bash_profile
source ~/.bash_profile

# Story-Geth 바이너리 다운로드 및 설치
echo -e "${YELLOW}Story-Geth 바이너리 다운로드 중...${NC}"
download_and_install "https://story-geth-binaries.s3.us-west-1.amazonaws.com/geth-public/geth-linux-arm-0.9.3-b224fdf.tar.gz" "geth-linux-arm-0.9.3-b224fdf.tar.gz" "story-geth" "$HOME/go/bin"

# Story 바이너리 다운로드 및 설치
echo -e "${YELLOW}Story 바이너리 다운로드 중...${NC}"
download_and_install "https://story-geth-binaries.s3.us-west-1.amazonaws.com/story-public/story-linux-arm64-0.11.0-aac4bfe.tar.gz" "story-linux-arm64-0.11.0-aac4bfe.tar.gz" "story" "$HOME/go/bin"

# Iliad 노드 초기화
echo -e "${GREEN}노드 초기화 중... 사용할 모니커 이름을 입력해주세요:${NC}"
read MONIKER
story init --network iliad --moniker "$MONIKER"

# 피어 설정
echo -e "${GREEN}피어 설정 중...${NC}"
PEERS=$(curl -s -X POST https://rpc-story.josephtran.xyz -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"net_info","params":[],"id":1}' | jq -r '.result.peers[] | select(.connection_status.SendMonitor.Active == true) | "\(.node_info.id)@\(if .node_info.listen_addr | contains("0.0.0.0") then .remote_ip + ":" + (.node_info.listen_addr | sub("tcp://0.0.0.0:"; "")) else .node_info.listen_addr | sub("tcp://"; "") end)"' | tr '\n' ',' | sed 's/,$//' | awk '{print "\"" $0 "\""}')
sed -i "s/^persistent_peers *=.*/persistent_peers = $PEERS/" "$HOME/.story/story/config/config.toml"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}새 피어로 설정이 완료되었습니다.${NC}"
else
    echo -e "${RED}피어 설정 실패.${NC}"
fi

# Story-Geth 서비스 파일 생성
echo -e "${GREEN}Story-Geth 서비스 파일을 생성합니다...${NC}"
sudo tee /etc/systemd/system/story-geth.service > /dev/null <<EOF
[Unit]
Description=Story Geth Client
After=network.target

[Service]
User=root
ExecStart=/root/go/bin/story-geth --iliad --syncmode full
Restart=on-failure
RestartSec=3
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF

# Story 서비스 파일 생성
echo -e "${GREEN}Story 서비스 파일을 생성합니다...${NC}"
sudo tee /etc/systemd/system/story.service > /dev/null <<EOF
[Unit]
Description=Story Consensus Client
After=network.target

[Service]
User=root
ExecStart=/root/go/bin/story run
Restart=on-failure
RestartSec=3
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF

# Story 및 Story-Geth 서비스 시작
echo -e "${GREEN}서비스를 시작합니다...${NC}"
sudo systemctl daemon-reload && \
sudo systemctl enable story-geth && \
sudo systemctl enable story && \
sudo systemctl start story-geth && \
sudo systemctl start story

# 현재 사용 중인 포트 확인
used_ports=$(netstat -tuln | awk '{print $4}' | grep -o '[0-9]*$' | sort -u)

# 각 포트에 대해 ufw allow 실행
  for port in $used_ports; do
    echo -e "${GREEN}포트 ${port}을(를) 허용합니다.${NC}"
    sudo ufw allow $port/tcp
  done

# Story-Geth 로그 확인
sudo journalctl -u story-geth -f -o cat

# Story 로그 확인
sudo journalctl -u story -f -o cat

# 동기화 상태 확인
echo -e "${YELLOW}동기화 상태를 확인합니다."Catch_up" : false${NC}"
curl localhost:26657/status | jq

# 동기화 실행
sudo systemctl stop story
sudo systemctl stop story-geth

echo -e "${YELLOW}Geth-data를 다운로드 합니다.${NC}"
cd $HOME
rm -f Geth_snapshot.lz4
if curl -s --head https://vps6.josephtran.xyz/Story/Geth_snapshot.lz4 | head -n 1 | grep "200" > /dev/null; then
    echo "Snapshot found, downloading..."
    aria2c -x 16 -s 16 https://vps6.josephtran.xyz/Story/Geth_snapshot.lz4 -o Geth_snapshot.lz4
else
    echo "No snapshot found."
fi

echo -e "${YELLOW}스토리 데이터를 다운로드 합니다.${NC}"
cd $HOME
rm -f Story_snapshot.lz4
if curl -s --head https://vps6.josephtran.xyz/Story/Story_snapshot.lz4 | head -n 1 | grep "200" > /dev/null; then
    echo "Snapshot found, downloading..."
    aria2c -x 16 -s 16 https://vps6.josephtran.xyz/Story/Story_snapshot.lz4 -o Story_snapshot.lz4
else
    echo "No snapshot found."
fi

# priv_validator_state.json 백업
mv $HOME/.story/story/data/priv_validator_state.json $HOME/.story/priv_validator_state.json.backup

# 오래된 데이터 제거
rm -rf ~/.story/story/data
rm -rf ~/.story/geth/iliad/geth/chaindata

# 스토리 데이터 추출
sudo mkdir -p /root/.story/story/data
lz4 -d Story_snapshot.lz4 | pv | sudo tar xv -C /root/.story/story/

# Geth-data 추출
sudo mkdir -p /root/.story/geth/iliad/geth/chaindata
lz4 -d Geth_snapshot.lz4 | pv | sudo tar xv -C /root/.story/geth/iliad/geth/

# priv_validator_state.json을 다시 이동합니다.
mv $HOME/.story/priv_validator_state.json.backup $HOME/.story/story/data/priv_validator_state.json

#노드 재시작
sudo systemctl start story
sudo systemctl start story-geth

# 사용자로부터 private key 입력 받기
story validator export --export-evm-key
echo -e "${YELLOW}Private key를 입력해주세요:${NC}"
read PRIVATE_KEY
echo "$PRIVATE_KEY" > $HOME/.story/story/config/private_key.txt

# Validator 등록을 위한 프라이빗 키 입력 및 저장
echo -e "${YELLOW}Validator 프라이빗 키를 입력해주세요:${NC}"
read VALIDATOR_KEY
echo "$VALIDATOR_KEY" > $HOME/.story/story/config/priv_validator_key.json

# Validator 등록
echo -e "${GREEN}Validator등록을 위해 최소 1개의 IP가 월렛에 있어야합니다.${NC}"
echo -e "${GREEN}해당사이트에서 faucet을 받아주세요: https://faucet.story.foundation/${NC}"
story validator create --stake 1000000000000000000 --private-key $PRIVATE_KEY

# Validator 정보
curl -s localhost:26657/status | jq -r '.result.validator_info' 

echo -e "${GREEN}모든 작업이 완료되었습니다. 컨트롤+A+D로 스크린을 종료해주세요.${NC}"
echo -e "${GREEN}스크립트 작성자: https://t.me/kjkresearch${NC}"
