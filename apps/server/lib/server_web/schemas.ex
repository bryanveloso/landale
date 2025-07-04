defmodule ServerWeb.Schemas do
  @moduledoc """
  OpenAPI schemas for all API endpoints.
  """

  alias OpenApiSpex.Schema

  defmodule SuccessResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        success: %Schema{type: :boolean, example: true},
        data: %Schema{type: :object, additionalProperties: true}
      },
      required: [:success, :data]
    })
  end

  defmodule ErrorResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        success: %Schema{type: :boolean, example: false},
        error: %Schema{type: :string, example: "Service unavailable"}
      },
      required: [:success, :error]
    })
  end

  defmodule HealthStatus do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        status: %Schema{type: :string, example: "healthy"},
        timestamp: %Schema{type: :integer, example: 1_640_995_200},
        uptime: %Schema{
          type: :object,
          properties: %{
            seconds: %Schema{type: :integer, example: 86_400},
            formatted: %Schema{type: :string, example: "1d 0h 0m"}
          }
        },
        memory: %Schema{
          type: :object,
          properties: %{
            total: %Schema{type: :string, example: "256.5 MB"},
            processes: %Schema{type: :string, example: "128.2 MB"},
            system: %Schema{type: :string, example: "128.3 MB"}
          }
        },
        services: %Schema{
          type: :object,
          additionalProperties: %Schema{
            type: :object,
            properties: %{
              connected: %Schema{type: :boolean},
              status: %Schema{type: :string}
            }
          }
        }
      },
      required: [:status, :timestamp, :uptime, :memory, :services]
    })
  end

  defmodule ServiceStatus do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        connected: %Schema{type: :boolean, example: true},
        status: %Schema{type: :string, example: "healthy"}
      },
      required: [:connected]
    })
  end

  defmodule OBSStatus do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        connected: %Schema{type: :boolean, example: true},
        connection_state: %Schema{type: :string, example: "connected"}
      },
      required: [:connected, :connection_state]
    })
  end

  defmodule OBSScenes do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        scenes: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              sceneName: %Schema{type: :string, example: "Main Scene"},
              sceneIndex: %Schema{type: :integer, example: 0}
            }
          }
        },
        currentProgramSceneName: %Schema{type: :string, example: "Main Scene"}
      }
    })
  end

  defmodule OBSStreamStatus do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        outputActive: %Schema{type: :boolean, example: true},
        outputReconnecting: %Schema{type: :boolean, example: false},
        outputTimecode: %Schema{type: :string, example: "01:23:45.678"},
        outputDuration: %Schema{type: :integer, example: 5_025_678},
        outputCongestion: %Schema{type: :number, example: 0.0},
        outputBytes: %Schema{type: :integer, example: 1_024_000},
        outputSkippedFrames: %Schema{type: :integer, example: 0},
        outputTotalFrames: %Schema{type: :integer, example: 5000}
      }
    })
  end

  defmodule TwitchStatus do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        connected: %Schema{type: :boolean, example: true},
        connection_state: %Schema{type: :string, example: "connected"},
        session_id: %Schema{type: :string, example: "AQoQexAWVYKSTIu4ec_2VAxyuhAB"},
        subscription_count: %Schema{type: :integer, example: 15},
        subscription_cost: %Schema{type: :integer, example: 18}
      },
      required: [:connected, :connection_state, :subscription_count, :subscription_cost]
    })
  end

  defmodule TwitchSubscription do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        id: %Schema{type: :string, example: "f1c2a387-161a-49f9-a165-0f21d7a4e1c4"},
        status: %Schema{type: :string, example: "enabled"},
        type: %Schema{type: :string, example: "channel.follow"},
        version: %Schema{type: :string, example: "2"},
        condition: %Schema{
          type: :object,
          properties: %{
            broadcaster_user_id: %Schema{type: :string, example: "12345"},
            moderator_user_id: %Schema{type: :string, example: "12345"}
          }
        },
        transport: %Schema{
          type: :object,
          properties: %{
            method: %Schema{type: :string, example: "websocket"},
            session_id: %Schema{type: :string, example: "AQoQexAWVYKSTIu4ec_2VAxyuhAB"}
          }
        },
        created_at: %Schema{type: :string, format: :datetime},
        cost: %Schema{type: :integer, example: 1}
      },
      required: [:id, :status, :type, :version, :condition, :transport, :created_at, :cost]
    })
  end

  defmodule TwitchSubscriptionTypes do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        stream: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              type: %Schema{type: :string, example: "stream.online"},
              description: %Schema{type: :string, example: "Stream goes live"},
              scopes: %Schema{type: :array, items: %Schema{type: :string}},
              version: %Schema{type: :string, example: "1"}
            }
          }
        },
        channel: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              type: %Schema{type: :string, example: "channel.follow"},
              description: %Schema{type: :string, example: "New follower"},
              scopes: %Schema{type: :array, items: %Schema{type: :string, example: "moderator:read:followers"}},
              version: %Schema{type: :string, example: "2"}
            }
          }
        },
        user: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              type: %Schema{type: :string, example: "user.update"},
              description: %Schema{type: :string, example: "User information updated"},
              scopes: %Schema{type: :array, items: %Schema{type: :string}},
              version: %Schema{type: :string, example: "1"}
            }
          }
        }
      }
    })
  end

  defmodule IronmonChallenge do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        id: %Schema{type: :integer, example: 1},
        name: %Schema{type: :string, example: "Elite Four Challenge"},
        description: %Schema{type: :string, example: "Complete the Elite Four with specific rules"},
        rules: %Schema{type: :string, example: "No items in battle, Set mode"},
        inserted_at: %Schema{type: :string, format: :datetime},
        updated_at: %Schema{type: :string, format: :datetime}
      },
      required: [:id, :name]
    })
  end

  defmodule IronmonCheckpoint do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        id: %Schema{type: :integer, example: 1},
        name: %Schema{type: :string, example: "Gym Leader Brock"},
        order: %Schema{type: :integer, example: 1},
        challenge_id: %Schema{type: :integer, example: 1},
        inserted_at: %Schema{type: :string, format: :datetime},
        updated_at: %Schema{type: :string, format: :datetime}
      },
      required: [:id, :name, :order, :challenge_id]
    })
  end

  defmodule IronmonResult do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        id: %Schema{type: :integer, example: 1},
        result: %Schema{type: :string, example: "win"},
        seed_id: %Schema{type: :integer, example: 1},
        checkpoint_id: %Schema{type: :integer, example: 1},
        completed_at: %Schema{type: :string, format: :datetime},
        inserted_at: %Schema{type: :string, format: :datetime},
        updated_at: %Schema{type: :string, format: :datetime}
      },
      required: [:id, :result, :seed_id, :checkpoint_id]
    })
  end

  defmodule CreateTwitchSubscription do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        type: %Schema{type: :string, example: "channel.follow"},
        condition: %Schema{
          type: :object,
          properties: %{
            broadcaster_user_id: %Schema{type: :string, example: "12345"},
            moderator_user_id: %Schema{type: :string, example: "12345"}
          }
        }
      },
      required: [:type, :condition]
    })
  end

  defmodule RainwaveStatus do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        success: %Schema{type: :boolean, example: true},
        data: %Schema{
          type: :object,
          properties: %{
            rainwave: %Schema{
              type: :object,
              properties: %{
                enabled: %Schema{type: :boolean, example: true},
                listening: %Schema{type: :boolean, example: true},
                station_id: %Schema{type: :integer, example: 3},
                station_name: %Schema{type: :string, example: "Covers"},
                has_credentials: %Schema{type: :boolean, example: true},
                current_song: %Schema{
                  type: :object,
                  nullable: true,
                  properties: %{
                    title: %Schema{type: :string, example: "Song Title"},
                    artist: %Schema{type: :string, example: "Artist Name"},
                    album: %Schema{type: :string, example: "Album Name"},
                    length: %Schema{type: :integer, example: 240},
                    start_time: %Schema{type: :integer, example: 1_640_995_200},
                    end_time: %Schema{type: :integer, example: 1_640_995_440},
                    url: %Schema{type: :string, example: "https://rainwave.cc/song/12345"},
                    album_art: %Schema{type: :string, nullable: true, example: "https://rainwave.cc/path/art_320.jpg"}
                  }
                }
              },
              required: [:enabled, :listening, :station_id, :station_name, :has_credentials]
            },
            timestamp: %Schema{type: :string, format: :"date-time"}
          },
          required: [:rainwave, :timestamp]
        }
      },
      required: [:success, :data]
    })
  end

  defmodule RainwaveConfig do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        enabled: %Schema{type: :boolean, example: true, description: "Enable or disable the Rainwave service"},
        station_id: %Schema{
          type: :integer,
          example: 3,
          description: "Rainwave station ID (1=Game, 2=OCRemix, 3=Covers, 4=Chiptunes, 5=All)",
          minimum: 1,
          maximum: 5
        }
      }
    })
  end

  defmodule TokenStatus do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        service: %Schema{type: :string, example: "twitch", description: "OAuth service name"},
        connected: %Schema{type: :boolean, example: true, description: "Service connection status"},
        token_valid: %Schema{type: :boolean, example: true, description: "Token validity status"},
        expires_at: %Schema{
          type: :string,
          format: :datetime,
          example: "2024-08-15T10:30:00Z",
          description: "Token expiration timestamp (ISO 8601)"
        },
        scopes: %Schema{
          type: :array,
          items: %Schema{type: :string},
          example: ["channel:read:subscriptions", "moderator:read:followers"],
          description: "OAuth scopes granted to the token"
        },
        last_validated: %Schema{
          type: :string,
          example: "2024-07-03T20:00:00Z",
          description: "Last time token was validated"
        },
        error: %Schema{
          type: :string,
          example: "Token expired",
          description: "Error message if token is invalid"
        }
      },
      required: [:service, :connected, :token_valid]
    })
  end

  defmodule TokenStatusResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        success: %Schema{type: :boolean, example: true},
        data: %Schema{
          type: :object,
          properties: %{
            twitch: TokenStatus
          },
          additionalProperties: TokenStatus,
          description: "OAuth token status for each service"
        }
      },
      required: [:success, :data]
    })
  end

  defmodule ContextResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        status: %Schema{type: :string, example: "success"},
        data: %Schema{
          type: :object,
          properties: %{
            started: %Schema{type: :string, format: :datetime, example: "2024-07-04T10:00:00Z"},
            ended: %Schema{type: :string, format: :datetime, example: "2024-07-04T10:02:00Z"},
            session: %Schema{type: :string, example: "stream_2024_07_04"},
            duration: %Schema{type: :number, example: 120.0},
            sentiment: %Schema{type: :string, example: "positive"},
            topics: %Schema{type: :array, items: %Schema{type: :string}, example: ["coding", "react"]}
          }
        }
      },
      required: [:status, :data]
    })
  end

  defmodule ContextListResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        status: %Schema{type: :string, example: "success"},
        data: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              started: %Schema{type: :string, format: :datetime, example: "2024-07-04T10:00:00Z"},
              ended: %Schema{type: :string, format: :datetime, example: "2024-07-04T10:02:00Z"},
              session: %Schema{type: :string, example: "stream_2024_07_04"},
              transcript: %Schema{type: :string, example: "Hello everyone, let's start coding..."},
              duration: %Schema{type: :number, example: 120.0},
              sentiment: %Schema{type: :string, example: "positive"},
              topics: %Schema{type: :array, items: %Schema{type: :string}, example: ["coding", "react"]},
              chat_summary: %Schema{type: :object, nullable: true},
              interactions_summary: %Schema{type: :object, nullable: true},
              emotes_summary: %Schema{type: :object, nullable: true}
            }
          }
        }
      },
      required: [:status, :data]
    })
  end

  defmodule ContextStatsResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        status: %Schema{type: :string, example: "success"},
        data: %Schema{
          type: :object,
          properties: %{
            overall: %Schema{
              type: :object,
              properties: %{
                total_count: %Schema{type: :integer, example: 150},
                total_duration: %Schema{type: :number, example: 18000.0},
                unique_sessions: %Schema{type: :integer, example: 3},
                avg_duration: %Schema{type: :number, example: 120.0}
              }
            },
            sentiment_distribution: %Schema{
              type: :array,
              items: %Schema{
                type: :object,
                properties: %{
                  sentiment: %Schema{type: :string, example: "positive"},
                  count: %Schema{type: :integer, example: 75}
                }
              }
            },
            popular_topics: %Schema{
              type: :array,
              items: %Schema{
                type: :object,
                properties: %{
                  topic: %Schema{type: :string, example: "coding"},
                  count: %Schema{type: :integer, example: 42}
                }
              }
            },
            time_window_hours: %Schema{type: :integer, example: 24}
          }
        }
      },
      required: [:status, :data]
    })
  end
end
