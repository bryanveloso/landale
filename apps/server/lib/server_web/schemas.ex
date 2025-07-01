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
        challenge_id: %Schema{type: :integer, example: 1},
        name: %Schema{type: :string, example: "Brock"},
        description: %Schema{type: :string, example: "First Gym Leader"},
        order: %Schema{type: :integer, example: 1},
        inserted_at: %Schema{type: :string, format: :datetime},
        updated_at: %Schema{type: :string, format: :datetime}
      },
      required: [:id, :challenge_id, :name, :order]
    })
  end

  defmodule IronmonResult do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        id: %Schema{type: :integer, example: 1},
        seed_id: %Schema{type: :integer, example: 12_345},
        checkpoint_id: %Schema{type: :integer, example: 1},
        result: %Schema{type: :string, example: "win"},
        notes: %Schema{type: :string, example: "Close battle, good strategy"},
        inserted_at: %Schema{type: :string, format: :datetime},
        updated_at: %Schema{type: :string, format: :datetime}
      },
      required: [:id, :seed_id, :checkpoint_id, :result]
    })
  end

  defmodule CreateTwitchSubscription do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        event_type: %Schema{type: :string, example: "channel.follow"},
        condition: %Schema{
          type: :object,
          properties: %{
            broadcaster_user_id: %Schema{type: :string, example: "12345"},
            moderator_user_id: %Schema{type: :string, example: "12345"}
          },
          additionalProperties: true
        },
        opts: %Schema{type: :array, items: %Schema{type: :string}, default: []}
      },
      required: [:event_type, :condition]
    })
  end
end
